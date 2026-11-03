"""Reference-axis M32 measured-output aggregation; no synthetic replacement pixels."""
from pathlib import Path
import csv
import json
import numpy as np


def finalize(plan, output, real, imag, mask, summary, render):
    output=Path(output)
    complete=mask.all(axis=2)
    summed=(real+1j*imag).sum(axis=-1)
    coherent=np.mean(abs(summed)**2,axis=2)
    coherent[~complete]=np.nan
    with np.load(output/'scan_results.npz') as prior:data={name:prior[name] for name in prior.files}
    distance=(np.asarray(plan.meta['relative_lag_samples'])+1)*7.68
    data.update(relative_group_range_km=distance,reference_script_range_km=distance,
        coherent_sum_re_rescaled=summed.real,coherent_sum_im_rescaled=summed.imag,
        coherent_power=coherent,range_calibrated=False)
    np.savez_compressed(output/'scan_results.npz',**data)
    with (output/'ionogram_power.csv').open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.writer(stream)
        writer.writerow(['frequency_mhz','relative_lag_samples','reference_script_range_km',
            'verified_blocks','required_blocks','mean_beam_power','coherent32_power','source'])
        for fp,freq in enumerate(plan.meta['frequency_mhz']):
            for lp,lag in enumerate(plan.meta['relative_lag_samples']):
                writer.writerow([freq,lag,distance[lp],int(mask[fp,lp].sum()),plan.nb,
                    data['power'][fp,lp] if complete[fp,lp] else '',
                    coherent[fp,lp] if complete[fp,lp] else '',summary['source']])
    summary.update(preprocessing=plan.meta['preprocessing'],
        reference_files_sha256=plan.meta['reference_files_sha256'],
        range_conversion='HF readall reference convention (lag+1)*7.68km; not absolute calibration',
        primary_figure_metric='coherent_power: mean_over_independent_blocks(abs(sum_32_complex_outputs)^2)',
        secondary_figure_metric='power: mean(abs(complex_output)^2)',
        coherent_records_per_weight_set=32,joint_512_record_weights=False,
        primary_figure='ionogram.png',secondary_figure='ionogram_noncoherent.png')
    if render:
        summary['plot']=plot(output,plan,coherent,summary['source'],summary['verified_frames'],True)
        summary['noncoherent_plot']=plot(output,plan,data['power'],summary['source'],summary['verified_frames'],False)
    (output/'scan_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    (output/'说明.txt').write_text(
        f"来源：{summary['source']}（hardware=实际板卡回包；emulator=协议自测，不能作为实测）\n"
        f"已验证{summary['verified_frames']}/{plan.meta['frames']}帧。实际m255a码表、4相位分别相关，每周期16通道IQ进入FPGA，每帧32周期独立MVDR。\n"
        "ionogram.png：同组权值下32个实际复数波束输出先求和再取功率；多个块分别求和取功率后平均，绝不跨不同权值块直接复数相加。\n"
        "主图按每频点中位功率/ln2估计背景显示0..40dB，属于背景估计，不能声称物理SNR或严格CFAR；未作显示背景抑制。\n"
        "ionogram_noncoherent.png：输出功率平均对照，色标为共同峰值0dB。两图的统计和色标不同，不能直接按亮度比较SNR。\n"
        "beam_records.csv：逐周期实际I/Q及还原增益；ionogram_power.csv：相干32功率和功率平均；scan_results.npz保留对应数组与未完成掩码。\n"
        "NPZ的power仍表示功率平均；coherent_power表示每块32复数求和后功率。所有分量先除以本位置量化gain，无输入削顶。\n"
        "scan.sqlite3保存原始配置/IQ和真实ACK/RESULT；缺失点保持NaN/空白/灰色，不用模型补填。\n"
        "距离沿用HF参考脚本(lag+1)*7.68km，未绝对校准。阵列映射/导向仍为假设。不是512周期联合求权/相干积累，也未实现ESB。\n",
        encoding='utf-8-sig')
    return summary


def plot(output,plan,power,mode,verified,coherent):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    from plot_m_ionogram import edges
    font_path='C:/Windows/Fonts/msyh.ttc'
    font_manager.fontManager.addfont(font_path)
    font=font_manager.FontProperties(fname=font_path).get_name()
    valid=np.isfinite(power)
    if coherent:
        background=np.full((plan.nf,1),np.nan)
        for fi in range(plan.nf):
            if valid[fi].any():background[fi,0]=max(float(np.median(power[fi,valid[fi]])/np.log(2)),1e-30)
        data=10*np.log10(np.maximum(power,1e-30)/background)
        lo,hi=0.,40.
        bar='背景相对功率（dB，中位数/ln2估计；非校准SNR）'
        method='32周期复数相干求和；同一帧同组权值'
        reference=dict(background_by_frequency=background[:,0].tolist(),method='median_power/ln2')
    else:
        peak=float(power[valid].max()) if valid.any() else 1.
        peak=max(peak,1e-30);data=10*np.log10(np.maximum(power,1e-30)/peak)
        lo=float(data[valid].min()) if valid.any() else -1.
        hi=0.
        if lo>=hi:lo=hi-1
        bar='相对功率（dB，已完成像素共同峰值=0）'
        method='32周期输出功率平均（对照图）'
        reference=dict(reference_power=peak,method='shared_peak')
    fi=np.asarray(plan.meta['source_frequency_index'],int)
    freq=np.asarray(plan.meta['frequency_mhz'])
    fstep=(freq[-1]-freq[0])/(fi[-1]-fi[0]) if len(fi)>1 else .5
    lags=np.asarray(plan.meta['relative_lag_samples'],int)
    step=min(4,int(np.gcd.reduce(np.diff(lags)))) if len(lags)>1 else 4
    dense_f=np.arange(fi[0],fi[-1]+1)*fstep+(freq[0]-fi[0]*fstep)
    dense_l=np.arange(lags[0],lags[-1]+1,step)
    dense_d=(dense_l+1)*7.68
    display=np.full((len(dense_f),len(dense_l)),np.nan)
    display[np.ix_(fi-fi[0],(lags-lags[0])//step)]=data
    def boundaries(a,spacing):return edges(a) if len(a)>1 else np.array([a[0]-spacing/2,a[0]+spacing/2])
    cmap=plt.get_cmap('viridis').copy();cmap.set_bad('#bbbbbb')
    source='实板回包' if mode=='hardware' else '协议自测（非实板、非回波测量）'
    filename='ionogram.png' if coherent else 'ionogram_noncoherent.png'
    with plt.rc_context({'font.family':font,'font.size':12,'axes.unicode_minus':False}):
        fig=plt.figure(figsize=(9,7.6));ax=fig.add_axes([.12,.24,.66,.58]);cax=fig.add_axes([.81,.24,.025,.58])
        mesh=ax.pcolormesh(boundaries(dense_f,fstep),boundaries(dense_d,step*7.68),
            np.ma.masked_invalid(display.T),cmap=cmap,vmin=lo,vmax=hi,shading='flat',rasterized=True)
        ax.set(xlabel='名义频率（MHz）',ylabel='参考脚本群距离（km；未校准）')
        ax.set_ylim(bottom=0)
        fig.suptitle(f'M实际参考码 · MVDR · {source}\n{method} · 已验证{verified}/{plan.meta["frames"]}帧',fontsize=15,y=.96)
        fig.colorbar(mesh,cax=cax,label=bar,extend='both' if coherent else 'neither')
        fig.text(.5,.045,'实际m255a码表；4相位独立相关；每帧16通道×32周期，独立求权。\n'
            '只显示已核对回包；缺失为灰色，无插值、平滑或参考值补填。\n'
            '距离沿用(lag+1)×7.68km；阵列映射/指向及距离零点未校准。\n'
            '多个32周期块仍独立求权，不等于512周期联合求权。',ha='center',va='bottom',fontsize=9)
        fig.savefig(Path(output)/filename,dpi=180,facecolor='white');plt.close(fig)
    return dict(filename=filename,db_limits=[lo,hi],reference=reference,
        below_display_limit=int((data[valid]<lo).sum()),above_display_limit=int((data[valid]>hi).sum()),
        raw_values_retained=True,interpolation=False,smoothing=False,missing_colour='#bbbbbb')
