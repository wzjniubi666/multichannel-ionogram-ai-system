"""Run fixed-parameter best.pt prefix on real FPGA for several ionograms."""
from pathlib import Path
import os,time,json,hashlib,secrets,sys,csv
import numpy as np
import torch,cv2
ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
os.environ['YOLO_CONFIG_DIR']=str(ROOT/'host/deploy/recognition/ultralytics_config')
sys.path.insert(0,str(ROOT/'host/app/recognition/vendor'))
from ultralytics import YOLO
from ultralytics.utils import ops
from udp_transport import Board
torch.set_num_threads(4)

def read_image(p):return cv2.imdecode(np.fromfile(str(p),dtype=np.uint8),cv2.IMREAD_COLOR)
def save_image(p,img):
    ok,data=cv2.imencode('.jpg',img)
    if not ok:raise RuntimeError('Image encode failed')
    data.tofile(str(p))
def boxes(pred,x,image,net):
    det=ops.non_max_suppression(pred,conf_thres=.25,iou_thres=.45,agnostic=False)[0]
    det[:,:4]=ops.scale_boxes(x.shape[2:],det[:,:4],image.shape).round()
    return [dict(class_name=net.names[int(row[5])],confidence=float(row[4]),xyxy=[float(v) for v in row[:4]]) for row in det.tolist()]
def draw(image,objects,title):
    im=image.copy()
    for ob in objects:
        x1,y1,x2,y2=map(int,ob['xyxy']);cv2.rectangle(im,(x1,y1),(x2,y2),(0,200,0),2)
        cv2.putText(im,f"{ob['class_name']} {ob['confidence']:.2f}",(x1,max(18,y1-6)),cv2.FONT_HERSHEY_SIMPLEX,.55,(0,0,255),2)
    cv2.putText(im,title,(12,24),cv2.FONT_HERSHEY_SIMPLEX,.65,(0,0,255),2)
    return im
def download(board):
    v=[]
    for pos in range(0,32768,360):v.extend(board.rd(0x400000+4*pos,min(360,32768-pos)))
    return np.asarray(v,dtype='<u4').view('<i2').reshape(32,32,64).transpose(2,0,1)[None].copy()
def main():
    out=ROOT/'metrics/runs/recognition/cli';out.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((ROOT/'fpga/build/recognition/board_case/manifest.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((ROOT/'host/model/recognition/best.pt').read_bytes()).hexdigest()==manifest['model_sha256']
    evidence={'sha256':json.loads((ROOT/'report/recognition_integrity.json').read_text())}
    for name,sha in evidence['sha256'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==sha,name
    with (ROOT/'fpga/build/recognition/board_case/negotiation.csv').open() as f:link_rows=list(csv.DictReader(f))
    status=int(link_rows[-1]['physr_hex'],16)
    diagnostic=(ROOT/'fpga/build/recognition/board_case/diagnostic_summary.txt').read_text()
    rxkhz=int(next(line.split()[1] for line in diagnostic.splitlines() if line.startswith('RX_CLOCK_KHZ ')))
    if (status&12)!=12 or ((status>>4)&3)!=2 or not 124000<=rxkhz<=126000:raise RuntimeError('Live gigabit PHY verification failed')
    link=dict(phy_reported_mbps=1000,full_duplex=True,rx_clock_khz=rxkhz,physr_hex=f'{status:04x}')
    net=YOLO(str(ROOT/'host/model/recognition/best.pt')).model.eval().fuse(verbose=False)
    board=Board();reports=[];tiles=[]
    try:
        if board.rd(12)[0]!=0x594f4c47:raise RuntimeError('New ionogram FPGA configuration is not loaded')
        for case in sorted((ROOT/'metrics/evidence/recognition/fixtures').glob('image*.npz')):
            data=np.load(case);image_path=resolve_asset(str(data['image_path']));image=read_image(image_path)
            x=torch.from_numpy(data['x']);words=data['words'].tolist();nonce=secrets.randbits(30)
            before=board.packets;retries=board.retries
            began=time.perf_counter()
            for pos in range(0,len(words),360):board.wr(0x100000+4*pos,words[pos:pos+360])
            uploaded=time.perf_counter();board.compute(nonce);cycles=board.rd(8)[0];computed=time.perf_counter()
            feature=download(board);downloaded=time.perf_counter()
            if not np.array_equal(feature,data['golden']):
                bad=np.argwhere(feature!=data['golden']);i=tuple(bad[0]);raise RuntimeError(f'{case.name}: {len(bad)} output mismatches, first {i}: {feature[i]} != {data["golden"][i]}')
            debug=np.asarray(board.rd(0x1000,60),dtype='<u4').view('<i4').reshape(15,4)
            if not np.array_equal(debug,data['debug']):raise RuntimeError('Intermediate accumulators differ')
            ends=np.asarray(board.rd(0x2000,15),dtype=np.int64)
            if np.any(np.diff(ends)<=0) or ends[-1]!=cycles or cycles!=3878912:raise RuntimeError('Invalid compute cycle trace')
            pixel=100*256+100;board.wr(0x100000+pixel*4,[words[pixel]^0xffffff]);board.compute(nonce+1)
            challenge=download(board)
            if not np.array_equal(challenge,data['challenge']) or np.array_equal(challenge,feature):raise RuntimeError('Changed-input live challenge failed')
            tensor=torch.from_numpy(feature.astype(np.float32)*data['out_scale'])
            with torch.no_grad():
                for _ in range(3):net(x)
                samples=[]
                for _ in range(10):
                    t=time.perf_counter();baseline=net(x)[0];samples.append((time.perf_counter()-t)*1000)
                forwards=[net.model[i].forward for i in range(5)];calls=[]
                def skip(i):
                    def f(inp):
                        if not torch.equal(inp,x):raise RuntimeError('Wrong input at hardware boundary')
                        calls.append(i);return tensor if i==4 else inp
                    return f
                try:
                    for i in range(5):net.model[i].forward=skip(i)
                    t=time.perf_counter();prediction=net(x)[0];remaining=(time.perf_counter()-t)*1000
                finally:
                    for i in range(5):net.model[i].forward=forwards[i]
                assert calls==list(range(5))
            objects=boxes(prediction,x,image,net);cpu_objects=boxes(baseline,x,image,net)
            stem=case.stem
            annotated=draw(image,objects,'FPGA 15 Conv + CPU remainder')
            cpu_image=draw(image,cpu_objects,'CPU FP32 baseline, same 256 input')
            save_image(out/f'{stem}_fpga.jpg',annotated);save_image(out/f'{stem}_cpu.jpg',cpu_image)
            np.save(out/f'{stem}_fpga_int16.npy',feature)
            tile=cv2.resize(annotated,(800,round(800*annotated.shape[0]/annotated.shape[1])))
            tiles.append(tile)
            report=dict(input_image=str(image_path),model_sha256=manifest['model_sha256'],ethernet_link=link,validation_mode='live_hardware',fpga_used=True,fpga_convolution_count=15,
                exact_output_values=int(feature.size),raw_accumulator_checks=60,live_changed_input_challenge_passed=True,
                nonce=nonce,cycles=cycles,fpga_compute_ms=cycles/80000,upload_ms=(uploaded-began)*1000,
                compute_and_poll_ms=(computed-uploaded)*1000,download_ms=(downloaded-computed)*1000,
                transfer_compute_ms=(downloaded-began)*1000,cpu_remaining_ms=remaining,
                fpga_path_ms=(downloaded-began)*1000+remaining,cpu_full_median_ms=float(np.median(samples)),
                udp_transactions=board.packets-before,udp_retries=board.retries-retries,input_shape=list(x.shape),
                confidence_threshold=.25,iou_threshold=.45,class_agnostic_nms=False,detections=objects,cpu_fp32_detections=cpu_objects,
                output_image=str(out/f'{stem}_fpga.jpg'),calibration='16 or fewer distinct training images; no dataset mAP validation',
                timing_note='Excludes programming, link negotiation, model loading, reference calculation, live challenge and image pre/postprocessing')
            report['speedup_vs_cpu']=report['cpu_full_median_ms']/report['fpga_path_ms']
            reports.append(report)
            (out/f'{stem}_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps({'image':stem,'detections':objects,'cpu_detections':cpu_objects,'fpga_path_ms':report['fpga_path_ms'],'retries':report['udp_retries']},ensure_ascii=False),flush=True)
    finally:board.sock.close()
    save_image(out/'overview.jpg',np.concatenate(tiles,axis=0))
    (out/'summary.json').write_text(json.dumps(dict(model=str(ROOT/'host/model/recognition/best.pt'),model_sha256=manifest['model_sha256'],ethernet_link=link,image_count=len(reports),fpga_verified_all=True,reports=reports),ensure_ascii=False,indent=2),encoding='utf-8')
    print('SUCCESS: real FPGA inference and changed-input checks passed on all images.',flush=True)
if __name__=='__main__':main()
