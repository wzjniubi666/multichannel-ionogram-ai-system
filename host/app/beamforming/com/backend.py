"""PUBLIC-HOST adapters around the sealed ACTIVE14 processing implementation."""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path
import ctypes
import json
import os
import re
import sys
import time
import uuid
import numpy as np

APP = Path(__file__).resolve().parent
from workspace_paths import locate_workspace
BASE = locate_workspace(APP)
PROJECT = BASE / 'XCK325Tboshuhecheng'
PYTHON = BASE / '.venv-cos/Scripts/python.exe'
REFERENCE = BASE / 'HFceshi'
RELEASE = PROJECT / 'validation/m_hf512_14ch_20261028'
sys.path.insert(0, str(PROJECT / 'python'))


class Cancelled(Exception):
    pass


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(path)


def stamp():
    return time.strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]


def is_admin():
    return os.name == 'nt' and bool(ctypes.windll.shell32.IsUserAnAdmin())


def owner_alive(pid):
    if not pid:
        return True
    if os.name != 'nt':
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    handle = kernel.OpenProcess(0x100000, False, int(pid))  # SYNCHRONIZE only
    if not handle:
        return False
    try:
        return kernel.WaitForSingleObject(ctypes.c_void_p(handle), 0) == 258
    finally:
        kernel.CloseHandle(ctypes.c_void_p(handle))


def cancelled(request):
    return Path(request['stop_file']).exists() or not owner_alive(request.get('owner_pid', 0))


def check_cancel(request):
    if cancelled(request):
        raise Cancelled('已请求停止，已保留完成的数据')


def validate_capture(folder, selected=None):
    from m_sequence_pipeline import MProfile, RawMCapture
    folder = Path(folder).resolve()
    if selected:
        paths = [Path(p).resolve() for p in selected]
        if len(paths) != 16 or len(set(paths)) != 16 or any(p.parent != folder for p in paths):
            raise ValueError('请选择同一文件夹中完整且不重复的16个COS文件')
        if set(paths) != set(folder.glob('*.cos')):
            raise ValueError('所选文件必须是同一时刻完整的00～15通道')
    capture = RawMCapture(folder, MProfile())
    fields = capture.prefix.split(',')
    if len(fields) < 5 or not re.fullmatch(r'\d{8}_\d{6}', fields[4]):
        raise ValueError('文件名缺少采集时间标识')
    return dict(folder=str(folder), capture=fields[4], files=[str(p) for p in capture.files],
                frequency_points=len(capture.frequency_mhz), frequencies=capture.frequency_mhz.tolist(),
                channels=16, active_channels=14, records=512,
                total_bytes=sum(p.stat().st_size for p in capture.files))


def verify_plan(path):
    from m512_active14_plan import Plan512
    from m512_active14_release import check_release
    plan = Plan512(path)
    check_release(plan)
    return plan


def find_plan(folder, quick, request, emit):
    from m_sequence_pipeline import sha256
    folder = Path(folder).resolve()
    expected_freq = [7.5, 10., 15.] if quick else None
    expected_lags = [20, 148, 244] if quick else list(range(0, 469, 4))
    for base in (APP / 'plans', RELEASE):
        for path in sorted(base.glob('*/plan.json')):
            check_cancel(request)
            try:
                meta = read_json(path)
                if Path(meta['capture_directory']).resolve() != folder:
                    continue
                if meta['relative_lag_samples'] != expected_lags:
                    continue
                if expected_freq and meta['frequency_mhz'] != expected_freq:
                    continue
                info = validate_capture(folder)
                if not quick and meta['frequency_mhz'] != info['frequencies']:
                    continue
                emit('stage', name='校验已有计划及原始文件', detail=str(path.parent))
                if any(sha256(row['path']) != row['sha256'] for row in meta['source']):
                    continue
                plan = verify_plan(path.parent)
                emit('log', message='复用已校验计划：' + str(plan.path))
                return plan
            except (OSError, ValueError, KeyError, AssertionError) as exc:
                emit('log', message='跳过不兼容缓存：' + str(exc))
    return None


@dataclass
class ResultData:
    path: Path
    summary: dict
    frequency: np.ndarray
    distance: np.ndarray
    board: np.ndarray
    single: np.ndarray
    complete: np.ndarray
    capture: str
    frequency_indices: np.ndarray
    lags: np.ndarray


def load_result(folder):
    from m512_active14_plan import Plan512
    folder = Path(folder).resolve()
    summary = read_json(folder / 'scan_summary.json')
    if summary.get('source') not in ('hardware', 'emulator') or summary.get('effective_channels') != 14:
        raise ValueError('请选择当前14路版本生成的结果目录')
    plan = Plan512(summary['plan_directory'])
    if summary['plan_sha256'] != plan.hash:
        raise ValueError('结果与计划哈希不匹配')
    with np.load(folder / 'scan_results.npz') as data:
        if str(data['source']) != summary['source'] or int(data['active_channel_mask']) != 0x7f7f:
            raise ValueError('结果来源或通道掩码不一致')
        frequency = data['frequency_mhz'].copy()
        distance = data['reference_script_range_km'].copy()
        complete = data['pixel_complete'].copy()
        board = data['coherent_power'].copy()
        actual = data['beam_re_rescaled'].sum(-1)**2 + data['beam_im_rescaled'].sum(-1)**2
        np.testing.assert_allclose(board, actual, rtol=0, atol=0, equal_nan=True)
    shape = (plan.nf, plan.nl)
    if board.shape != shape or int(complete.sum()) != summary['verified_frames']:
        raise ValueError('结果完成数或网格不一致')
    np.testing.assert_array_equal(frequency, plan.meta['frequency_mhz'])
    np.testing.assert_array_equal(distance, (np.asarray(plan.meta['relative_lag_samples']) + 1)*7.68)
    ii = plan.iq[:, :, 0, 0].astype(np.int64).sum(1).reshape(shape)/plan.gains
    qq = plan.iq[:, :, 0, 1].astype(np.int64).sum(1).reshape(shape)/plan.gains
    single = ii**2 + qq**2
    # Use the same verified pixel mask in both compared panels.
    single[~complete] = np.nan
    board[~complete] = np.nan
    return ResultData(folder, summary, frequency, distance, board, single, complete,
                      Path(plan.meta['capture_directory']).name,
                      np.asarray(plan.meta['source_frequency_index']),np.asarray(plan.meta['relative_lag_samples']))


def make_figure(data, view='mvdr', normalization='individual', figsize=(10, 5.9)):
    from matplotlib.figure import Figure
    from matplotlib import colormaps, font_manager
    from plot_m_ionogram import edges
    import warnings
    font = font_manager.FontProperties(fname='C:/Windows/Fonts/msyh.ttc')
    fig = Figure(figsize=figsize, dpi=110, facecolor='white')
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', RuntimeWarning)
        background_single = np.maximum(np.nanmedian(data.single, axis=1, keepdims=True)/np.log(2), 1e-30)
        background_board = np.maximum(np.nanmedian(data.board, axis=1, keepdims=True)/np.log(2), 1e-30)
    power = [data.single, data.board] if view == 'compare' else [data.single if view == 'single' else data.board]
    titles = ['通道00（未合成）', '14路MVDR']
    selected_titles = titles if view == 'compare' else [titles[0] if view == 'single' else titles[1]]
    axes = fig.subplots(1, len(power), sharex=True, sharey=True, squeeze=False)[0]
    fig.subplots_adjust(left=.09,right=.85,bottom=.19,top=.83,wspace=.14)
    cmap = colormaps['jet'].copy(); cmap.set_bad('#b7c1cc')
    indices=data.frequency_indices
    fstep=(data.frequency[-1]-data.frequency[0])/(indices[-1]-indices[0]) if len(indices)>1 else .5
    dense_frequency=data.frequency[0]+np.arange(indices[-1]-indices[0]+1)*fstep
    lstep=min(4,int(np.gcd.reduce(np.diff(data.lags)))) if len(data.lags)>1 else 4
    dense_lags=np.arange(data.lags[0],data.lags[-1]+1,lstep)
    dense_distance=(dense_lags+1)*7.68
    def boundaries(values, spacing):
        return edges(values) if len(values) > 1 else np.array([values[0]-spacing/2, values[0]+spacing/2])
    for ax, values, title in zip(axes, power, selected_titles):
        background = background_single if normalization == 'common' or title == titles[0] else background_board
        db = 10*np.log10(np.maximum(values, 1e-30)/background)
        display=np.full((len(dense_frequency),len(dense_lags)),np.nan)
        display[np.ix_(indices-indices[0],(data.lags-data.lags[0])//lstep)]=db
        mesh = ax.pcolormesh(boundaries(dense_frequency, fstep), boundaries(dense_distance, lstep*7.68),
                            np.ma.masked_invalid(display.T), cmap=cmap, vmin=0, vmax=40, shading='flat', rasterized=True)
        ax.set_ylim(0, boundaries(dense_distance, lstep*7.68)[-1])
        ax.set_title(title,fontproperties=font,fontsize=10,color='#526175',pad=9)
        ax.set_xlabel('频率（MHz）',fontproperties=font,color='#64748b')
        ax.tick_params(labelsize=9,colors='#6b7787',width=.6)
        for spine in ax.spines.values():spine.set_color('#cbd3de');spine.set_linewidth(.6)
    axes[0].set_ylabel('群距离（km）',fontproperties=font,color='#64748b')
    cax = fig.add_axes([.88, .19, .015, .64])
    bar = fig.colorbar(mesh, cax=cax, extend='both')
    bar.set_label('相对功率（dB）',fontproperties=font,fontsize=9,color='#64748b')
    bar.outline.set_visible(False);bar.ax.tick_params(labelsize=9,colors='#6b7787',width=.5)
    cap = data.capture
    label = f'{cap[:4]}-{cap[4:6]}-{cap[6:8]} {cap[9:11]}:{cap[11:13]}' if len(cap) == 15 else cap
    source_label='实板' if data.summary['source']=='hardware' else '模拟（非实板）'
    if data.summary.get('live_preview'):source_label+=' · 实时预览'
    fig.suptitle(f'{label}  ·  {source_label}',fontproperties=font,fontsize=13,color='#334155',y=.96)
    return fig


def export_figures(folder):
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    data = load_result(folder)
    output = Path(folder) / 'blue_figures'
    output.mkdir(exist_ok=True)
    products = []
    for name, view, norm in (('mvdr_blue', 'mvdr', 'individual'), ('single00_blue', 'single', 'individual'),
                              ('comparison_structure', 'compare', 'individual'), ('comparison_common', 'compare', 'common')):
        fig = make_figure(data, view, norm, (13, 7) if view == 'compare' else (9, 7))
        FigureCanvasAgg(fig)
        for suffix in ('png', 'pdf'):
            path = output / f'{name}.{suffix}'
            fig.savefig(path, dpi=180, facecolor='white')
            products.append(str(path))
    write_json(output / 'display_settings.json', dict(source=data.summary['source'],
        verified_frames=int(data.complete.sum()), plan_sha256=data.summary['plan_sha256'],
        colormap='jet', limits_db=[0,40], single_channel=0, integration='abs(sum512 complex IQ/gain)**2',
        background='median over verified lags per frequency / ln2; common or individual as labelled',
        smoothing=False, interpolation=False, original_result_files_modified=False))
    return products
