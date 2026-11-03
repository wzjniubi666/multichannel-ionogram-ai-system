"""Unified project paths and explicit, file-based handoff between FPGA stages."""
from pathlib import Path
from datetime import datetime
import hashlib,json,os,shutil,sys,uuid

ROOT=Path(__file__).resolve().parents[2]
SETTINGS=ROOT/'host/deploy/system_settings.json'

def settings():return json.loads(SETTINGS.read_text(encoding='utf-8-sig'))

def resolve_python(kind,config=None):
    config=settings() if config is None else config
    value=config.get(kind+'_python','').strip()
    if value:
        path=Path(value).expanduser()
        if not path.is_absolute():path=ROOT/path
        if path.is_file():return path.resolve()
        raise FileNotFoundError('Python路径不存在：'+str(path))
    if kind=='hub':return Path(sys.executable)
    if kind=='beamforming':
        for parent in ROOT.parents:
            path=parent/'.venv-cos/Scripts/python.exe'
            if path.is_file():return path
    if kind=='recognition':
        value=os.environ.get('YOLO_PYTHON','')
        if value and Path(value).is_file():return Path(value)
    raise FileNotFoundError('请在系统界面中选择'+('YOLO识别' if kind=='recognition' else '波束合成')+'使用的Python解释器。')

def recognition_command(image=None,config=None):
    command=[str(resolve_python('recognition',config)),'-X','utf8',str(ROOT/'host/app/recognition/app_gui.py')]
    if image is not None:
        image=Path(image).resolve(strict=True)
        command+=['--image',str(image)]
    return command

def child_environment():
    env=os.environ.copy()
    # The hub binds its own Tcl8.6.12. Conda's recognition interpreter must use its own Tcl.
    env.pop('TCL_LIBRARY',None);env.pop('TK_LIBRARY',None)
    env['PYTHONUTF8']='1';env['PYTHONDONTWRITEBYTECODE']='1'
    return env

def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest().upper()

def handoff_result(folder,output_root=None,allow_emulator=False):
    folder=Path(folder).resolve(strict=True)
    summary_path=folder/'scan_summary.json'
    summary=json.loads(summary_path.read_text(encoding='utf-8-sig'))
    source=summary.get('source')
    if source not in ('hardware','emulator') or (source=='emulator' and not allow_emulator):
        raise ValueError('默认只交接完整实板结果；离线模拟须明确选择允许模拟。')
    if summary.get('status')!='COMPLETE_'+source.upper():raise ValueError('扫描尚未完成，请完成/继续原任务后交接。')
    if summary.get('verified_frames')!=summary.get('planned_frames') or not summary.get('verified_frames'):
        raise ValueError('完成数与计划不一致，未交接图片。')
    if summary.get('effective_channels')!=14:raise ValueError('此交接入口要求当前14路波束合成结果。')
    image=folder/'blue_figures/mvdr_blue.png'
    if not image.is_file():raise FileNotFoundError('未找到blue_figures/mvdr_blue.png，请先在波束合成阶段完成图表导出。')
    from PIL import Image
    with Image.open(image) as im:im.verify()
    stamp=datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:6]
    output=Path(output_root or ROOT/'metrics/runs/handoff')/stamp
    output.mkdir(parents=True)
    target=output/'ionogram.png';shutil.copy2(image,target)
    digest=sha(image)
    if sha(target)!=digest:raise IOError('交接图片复制核验失败。')
    manifest=dict(source_result=str(folder),source=source,status=summary['status'],
        verified_frames=summary['verified_frames'],plan_sha256=summary.get('plan_sha256'),
        original_image=str(image),image_sha256=digest,output_image=str(target),
        summary_sha256=sha(summary_path),image_modified=False,recognition_executed=False,
        note='File handoff only; no hardware access, inference or accuracy claim. Detection starts explicitly in recognition UI.')
    (output/'handoff.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return target,manifest
