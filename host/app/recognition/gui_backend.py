"""One GUI job. JSON progress on stdout; real FPGA execution, never CPU fallback."""
from pathlib import Path
import argparse,json,os,sys,time,secrets,hashlib,csv,subprocess,traceback
ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
class Cancelled(Exception):pass
def emit(event,**values):print(json.dumps(dict(event=event,**values),ensure_ascii=False),flush=True)
def check_cancel(path):
    if path and Path(path).exists():raise Cancelled('任务已停止；下次识别将重新初始化板卡。')
def progress(value,message,**kw):emit('progress',percent=value,message=message,**kw)
def load_parameters():
    import numpy as np
    case=ROOT/'fpga/build/recognition/board_case'
    manifest=json.loads((case/'manifest.json').read_text(encoding='utf-8'))
    def mem(name,bits,signed=False):
        dtype={8:'u1',16:'<u2',24:'<u4',32:'<u4'}[bits]
        a=np.asarray([int(s,16) for s in (case/name).read_text().split()],dtype=dtype)
        return a.view({8:'i1',16:'<i2',32:'<i4'}[bits]) if signed else a
    lanes=np.stack([mem(f'w{i}.mem',8,True) for i in range(32)])
    biases=np.stack([mem(f'bias{i}.mem',32,True) for i in range(32)])
    coeff=mem('coeff.mem',24).astype(np.int64).reshape(16,64)
    table=mem('silu.mem',16,True).reshape(16,8192)
    weights=[];bs=[];offset=0
    for i,shape in enumerate(manifest['conv_shapes']):
        co,ci,kh,kw=shape;taps=ci*kh*kw
        w=np.stack([lanes[oc%32,offset+(oc//32)*taps:offset+(oc//32+1)*taps] for oc in range(co)]).reshape(shape)
        b=np.asarray([biases[oc%32,i*2+oc//32] for oc in range(co)],dtype=np.int32)
        weights.append(w);bs.append(b);offset+=((co+31)//32)*taps
    if offset!=manifest['weight_words_per_lane']:raise RuntimeError('权重布局与硬件不一致')
    return dict(manifest=manifest,weights=weights,biases=bs,coeff=coeff,table=table)
def preprocess(image):
    import cv2,numpy as np
    h,w=image.shape[:2];r=min(256/h,256/w);nw,nh=round(w*r),round(h*r)
    im=cv2.resize(image,(nw,nh));dw,dh=(256-nw)/2,(256-nh)/2
    im=cv2.copyMakeBorder(im,round(dh-.1),round(dh+.1),round(dw-.1),round(dw+.1),cv2.BORDER_CONSTANT,value=(114,114,114))
    x=np.ascontiguousarray(im[:,:,::-1].transpose(2,0,1)[None],dtype=np.float32)/255.
    return x,np.rint(x*255).astype(np.uint8)
def reference(xq,params,callback=None,cancel=None):
    import torch,numpy as np
    sources=[None,0,1,2,3,1,(4,5),6,7,8,9,10,11,7,(12,13)]
    residuals={4:2,10:8,12:10};strides=[2,2,1,1,1,1,1,2,1,1,1,1,1,1,1];pads=[2,1,0,0,1,0,0,1,0,0,1,0,1,0,0]
    ys=[];debug=[];clipped=[]
    for i in range(15):
        check_cancel(cancel);src=sources[i]
        inp=xq if src is None else np.concatenate([ys[s] for s in src],1) if isinstance(src,tuple) else ys[src]
        w=params['weights'][i];b=params['biases'][i]
        with torch.no_grad():
            acc=torch.nn.functional.conv2d(torch.from_numpy(inp.astype(np.float64)),torch.from_numpy(w.astype(np.float64)),torch.from_numpy(b.astype(np.float64)),stride=strides[i],padding=pads[i]).numpy()
        if np.max(np.abs(acc))>=(1<<31):raise RuntimeError(f'第 {i+1} 层累加范围超过当前硬件配置；请检查图片是否属于模型适用范围。')
        acc=acc.astype(np.int32);co=w.shape[0]
        idx=((acc.astype(np.int64)*params['coeff'][i,:co][None,:,None,None])>>24)+4096
        clipped.append(int(np.count_nonzero((idx<0)|(idx>8191))))
        q=params['table'][i][np.clip(idx,0,8191)]
        if i in residuals:q=np.clip(q.astype(np.int32)+ys[residuals[i]].astype(np.int32),-32768,32767).astype(np.int16)
        ys.append(q);debug.append(acc[0,:4,0,0])
        if callback:callback(i+1)
    return ys[-1],np.stack(debug),clipped
def packed(xq):
    import numpy as np
    p=xq[0].transpose(1,2,0).reshape(-1,3).astype(np.uint32)
    return p[:,0]|p[:,1]<<8|p[:,2]<<16
def link_info():
    with (ROOT/'fpga/build/recognition/board_case/negotiation.csv').open() as f:rows=list(csv.DictReader(f))
    status=int(rows[-1]['physr_hex'],16)
    text=(ROOT/'fpga/build/recognition/board_case/diagnostic_summary.txt').read_text()
    rx=int(next(s.split()[1] for s in text.splitlines() if s.startswith('RX_CLOCK_KHZ ')))
    if (status&12)!=12 or ((status>>4)&3)!=2 or not 124000<=rx<=126000:raise RuntimeError('未确认千兆全双工或 125MHz 接收时钟。')
    return dict(phy_reported_mbps=1000,full_duplex=True,rx_clock_khz=rx,physr_hex=f'{status:04x}',verified_at=(ROOT/'fpga/build/recognition/board_case/negotiation.csv').stat().st_mtime)
def initialize(cancel):
    from run_detection import vivado
    progress(8,'通过 JTAG 下载已验证的 FPGA 配置…')
    cmd=[vivado(),'-mode','batch','-source',str(ROOT/'fpga/build/recognition/diagnose.tcl'),'-log',str(ROOT/'metrics/logs/recognition/gui_board.log'),'-nojournal']
    with subprocess.Popen(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)) as p:
        for line in p.stdout:
            line=line.strip()
            if not line:continue
            emit('log',message=line)
            if 'program_hw_devices: Time' in line:progress(18,'配置已下载，正在检查 PHY 并重新协商千兆网口…')
            elif 'GIGABIT_ADVERTISEMENT_READBACK=' in line and not line.startswith('#'):progress(23,'等待千兆全双工链路稳定…')
        if p.wait()!=0:raise RuntimeError('板卡初始化失败，请检查供电、JTAG、网线和 Vivado 路径。详细信息见日志。')
    check_cancel(cancel)
    from udp_transport import Board
    b=Board()
    try:
        if b.rd(12)[0]!=0x594f4c47:raise RuntimeError('网口响应的 FPGA 配置不正确。')
    finally:b.sock.close()
    info=link_info();emit('connected',link=info);progress(28,'板卡已连接：1000 Mbps 全双工，FPGA 配置正确。')
    return info
def read_feature(board,callback=None,cancel=None):
    import numpy as np
    vals=[]
    for pos in range(0,32768,360):
        check_cancel(cancel);vals.extend(board.rd(0x400000+4*pos,min(360,32768-pos)))
        if callback and (pos//360)%6==0:callback(min(pos+360,32768),32768)
    return np.asarray(vals,dtype='<u4').view('<i2').reshape(32,32,64).transpose(2,0,1)[None].copy()
def annotate(image,objects):
    import cv2
    im=image.copy();scale=max(.65,im.shape[1]/1400);thick=max(2,round(im.shape[1]/450));stroke=max(1,round(im.shape[1]/1500))
    for ob in objects:
        x1,y1,x2,y2=map(int,ob['xyxy']);cv2.rectangle(im,(x1,y1),(x2,y2),(0,230,40),thick,cv2.LINE_AA)
        label=f"{ob['class_name']} {ob['confidence']*100:.1f}%";(tw,th),bl=cv2.getTextSize(label,cv2.FONT_HERSHEY_SIMPLEX,scale,stroke);pad=max(3,round(scale*3))
        cv2.rectangle(im,(x1,y1),(min(im.shape[1]-1,x1+tw+pad*2),min(im.shape[0]-1,y1+th+bl+pad*2)),(20,85,15),-1)
        cv2.putText(im,label,(x1+pad,y1+pad+th),cv2.FONT_HERSHEY_SIMPLEX,scale,(255,255,255),stroke,cv2.LINE_AA)
    return im
def identify(args,link):
    progress(30,'加载模型和固定量化参数…')
    sys.path.insert(0,str(ROOT/'host/app/recognition/vendor'));os.environ['YOLO_CONFIG_DIR']=str(ROOT/'host/deploy/recognition/ultralytics_config')
    import numpy as np,torch,cv2
    from ultralytics import YOLO
    from ultralytics.utils import ops
    from udp_transport import Board
    torch.set_num_threads(4)
    image_path=Path(args.image).resolve(strict=True)
    image=cv2.imdecode(np.fromfile(str(image_path),dtype=np.uint8),cv2.IMREAD_COLOR)
    if image is None:raise RuntimeError('无法读取图片，请选择 PNG、JPG、BMP、TIFF 或 WebP 图片。')
    check_cancel(args.cancel)
    params=load_parameters();net=YOLO(str(ROOT/'host/model/recognition/best.pt')).model.eval().fuse(verbose=False)
    x,xq=preprocess(image)
    progress(38,'为新图片生成精确整数校验参考（电脑执行，仅用于核验）…')
    golden,debug,clipped=reference(xq,params,lambda n:progress(38+n*.7,f'生成原图参考：{n}/15 层'),args.cancel)
    if sum(clipped):emit('log',message=f'本图有 {sum(clipped)} 个查表输入超出校准区间并被截断；数值仍会与 FPGA 严格核验，但检测精度可能下降。')
    changed=xq.copy();changed[0,:,100,100]^=255
    expected_challenge,_,_=reference(changed,params,lambda n:progress(49+n*.6,f'生成变化输入校验：{n}/15 层'),args.cancel)
    challenge_kind='pixel_100_100'
    if np.array_equal(golden,expected_challenge):
        changed=xq^255;challenge_kind='all_pixels_inverted'
        expected_challenge,_,_=reference(changed,params,cancel=args.cancel)
    if np.array_equal(golden,expected_challenge):raise RuntimeError('该图片无法形成有效的量化变化挑战，未输出未经充分核验的结果。')
    original_words=packed(xq).tolist();changed_words=packed(changed).tolist()
    board=Board()
    try:
        if board.rd(12)[0]!=0x594f4c47:raise RuntimeError('FPGA 未响应预期配置，请重新连接/初始化板卡。')
        nonce=secrets.randbits(30);began=time.perf_counter()
        for pos in range(0,65536,360):
            check_cancel(args.cancel);board.wr(0x100000+pos*4,original_words[pos:pos+360])
            if (pos//360)%10==0:progress(60+pos/65536*10,f'上传输入：{min(pos+360,65536)}/65536 字')
        uploaded=time.perf_counter();progress(71,'FPGA 正在执行前 15 个卷积…');board.compute(nonce);cycles=board.rd(8)[0];computed=time.perf_counter()
        progress(75,'读取 FPGA 特征…');hw=read_feature(board,lambda n,total:progress(75+n/total*8,f'读取特征：{n}/{total} 字'),args.cancel);downloaded=time.perf_counter()
        if not np.array_equal(hw,golden):raise RuntimeError(f'FPGA 特征不一致：{int(np.count_nonzero(hw!=golden))} 个值；已停止，未使用 CPU 结果代替。')
        raw=np.asarray(board.rd(0x1000,60),dtype='<u4').view('<i4').reshape(15,4)
        if not np.array_equal(raw,debug):raise RuntimeError('中间累加器校验失败。')
        ends=np.asarray(board.rd(0x2000,15),dtype=np.int64)
        if np.any(np.diff(ends)<=0) or ends[-1]!=cycles or cycles!=3878912:raise RuntimeError('FPGA 阶段计数不正确。')
        progress(85,'65536 个特征值及中间计算通过；执行变化输入挑战…')
        if challenge_kind=='pixel_100_100':board.wr(0x100000+(100*256+100)*4,[changed_words[100*256+100]])
        else:
            for pos in range(0,65536,360):check_cancel(args.cancel);board.wr(0x100000+pos*4,changed_words[pos:pos+360])
        board.compute(nonce+1);challenge=read_feature(board,cancel=args.cancel)
        if not np.array_equal(challenge,expected_challenge) or np.array_equal(challenge,hw):raise RuntimeError('实时变化输入挑战失败。')
        packets=board.packets;retries=board.retries
    finally:board.sock.close()
    check_cancel(args.cancel);progress(92,'真实 FPGA 校验通过，电脑完成剩余网络和检测框筛选…')
    tx=torch.from_numpy(x);feature=torch.from_numpy(hw.astype(np.float32)*np.float32(params['manifest']['activation_scales'][-1]))
    with torch.no_grad():
        start=time.perf_counter();baseline=net(tx)[0];cpu_full=(time.perf_counter()-start)*1000
        original=[net.model[i].forward for i in range(5)];calls=[]
        def skip(index):
            def f(inp):
                if not torch.equal(inp,tx):raise RuntimeError('FPGA 计算输入与后续网络不一致。')
                calls.append(index);return feature if index==4 else inp
            return f
        try:
            for i in range(5):net.model[i].forward=skip(i)
            start=time.perf_counter();pred=net(tx)[0];remaining=(time.perf_counter()-start)*1000
        finally:
            for i in range(5):net.model[i].forward=original[i]
        if calls!=list(range(5)):raise RuntimeError('FPGA 前缀替换不正确。')
    det=ops.non_max_suppression(pred,conf_thres=args.confidence,iou_thres=.45,agnostic=False)[0]
    det[:,:4]=ops.scale_boxes(tx.shape[2:],det[:,:4],image.shape).round()
    objects=[dict(class_name=net.names[int(row[5])],confidence=float(row[4]),xyxy=[float(v) for v in row[:4]]) for row in det.tolist()]
    out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
    result=out/'recognized.jpg';ok,buf=cv2.imencode('.jpg',annotate(image,objects))
    if not ok:raise RuntimeError('结果图片保存失败。')
    buf.tofile(str(result));np.save(out/'fpga_features_int16.npy',hw)
    report=dict(input_image=str(image_path),output_image=str(result),model_sha256=params['manifest']['model_sha256'],fpga_used=True,validation_mode='live_hardware',ethernet_link=link,
        convolution_count=15,exact_output_values=65536,raw_accumulator_checks=60,live_changed_input_challenge_passed=True,challenge_kind=challenge_kind,nonce=nonce,cycles=cycles,
        fpga_compute_ms=cycles/80000,upload_ms=(uploaded-began)*1000,compute_and_poll_ms=(computed-uploaded)*1000,download_ms=(downloaded-computed)*1000,cpu_remaining_ms=remaining,
        fpga_path_ms=(downloaded-began)*1000+remaining,cpu_full_single_unwarmed_ms=cpu_full,udp_transactions=packets,udp_retries=retries,input_shape=[1,3,256,256],detections=objects,
        confidence_threshold=args.confidence,lookup_clip_counts=clipped,calibration='Fixed 14 training-image calibration; arbitrary image accuracy not guaranteed; no dataset mAP evaluation',
        timing_note='fpga_path_ms excludes initialization, model loading, CPU reference generation, challenge verification and image drawing. CPU comparison is a single unwarmed run, not a benchmark.')
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    progress(100,f'识别完成：{len(objects)} 个目标，FPGA 计算 {cycles/80000:.2f} ms。')
    emit('result',report=report,report_path=str(out/'report.json'))
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--image');parser.add_argument('--output',required=True);parser.add_argument('--cancel');parser.add_argument('--reuse-board',action='store_true');parser.add_argument('--initialize-only',action='store_true');parser.add_argument('--confidence',type=float,default=.25)
    args=parser.parse_args();Path(args.output).mkdir(parents=True,exist_ok=True)
    if not .01<=args.confidence<=.99:raise RuntimeError('置信度阈值需要在 0.01～0.99 之间。')
    progress(2,'检查模型、量化参数与 FPGA 配置完整性…')
    hashes=json.loads((ROOT/'report/recognition_integrity.json').read_text())
    for name,digest in hashes.items():
        check_cancel(args.cancel)
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:raise RuntimeError('工程文件校验失败：'+name)
    check_cancel(args.cancel)
    link=None
    if args.reuse_board and not args.initialize_only:
        from udp_transport import Board
        b=None
        try:
            b=Board()
            if b.rd(12)[0]!=0x594f4c47:raise RuntimeError('配置已失效')
            link=link_info();emit('connected',link=link);progress(28,'复用当前已验证的板卡连接。')
        except (OSError,RuntimeError,ValueError):emit('log',message='上次连接已失效，重新下载配置并协商网口。')
        finally:
            if b:b.sock.close()
    if link is None:link=initialize(args.cancel)
    if args.initialize_only:progress(100,'板卡初始化完成，可拖入图片识别。');emit('initialized',link=link);return
    if not args.image:raise RuntimeError('未指定图片。')
    identify(args,link)
if __name__=='__main__':
    try:main()
    except Cancelled as e:emit('cancelled',message=str(e));sys.exit(2)
    except Exception as e:emit('error',message=str(e));emit('log',message=traceback.format_exc());sys.exit(1)
