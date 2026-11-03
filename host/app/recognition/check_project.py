from pathlib import Path
import hashlib,json,sys,os,ast
ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
def main():
    integrity=json.loads((ROOT/'report/recognition_integrity.json').read_text())
    for name,sha in integrity.items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=sha:raise RuntimeError(f'Integrity failed: {name}')
    for name in ['host/app/recognition/run_detection.py','host/app/recognition/test_images.py','host/app/recognition/prepare_cases.py','host/app/recognition/udp_transport.py']:
        ast.parse((ROOT/name).read_text(encoding='utf-8'))
    manifest=json.loads((ROOT/'fpga/build/recognition/board_case/manifest.json').read_text(encoding='utf-8'))
    for name in manifest['test_images']+manifest['calibration_images']:
        if Path(name).is_absolute() or not resolve_asset(name).is_file():raise RuntimeError(f'Invalid image path: {name}')
    if '--model' in sys.argv:
        os.environ['YOLO_CONFIG_DIR']=str(ROOT/'host/deploy/recognition/ultralytics_config')
        sys.path.insert(0,str(ROOT/'host/app/recognition/vendor'))
        import numpy as np,torch,cv2
        from ultralytics import YOLO
        import ultralytics
        from ultralytics.utils import ops
        if not Path(ultralytics.__file__).resolve().is_relative_to(ROOT/'host/app/recognition/vendor'):raise RuntimeError('Wrong YOLO source')
        net=YOLO(str(ROOT/'host/model/recognition/best.pt')).model.eval().fuse(verbose=False)
        torch.set_num_threads(4)
        for i,path in enumerate(sorted((ROOT/'metrics/evidence/recognition/fixtures').glob('image*.npz'))):
            with np.load(path) as data:
                x=torch.from_numpy(data['x']);feature=torch.from_numpy(data['golden'].astype(np.float32)*data['out_scale'])
                image=cv2.imdecode(np.fromfile(str(resolve_asset(str(data['image_path']))),dtype=np.uint8),cv2.IMREAD_COLOR)
                actual=np.load(ROOT/f'metrics/evidence/recognition/verified_results/image{i}_fpga_int16.npy')
                if not np.array_equal(actual,data['golden']):raise RuntimeError('Archived FPGA tensor mismatch')
            if image is None:raise RuntimeError('Image failed to load')
            forwards=[net.model[j].forward for j in range(5)]
            with torch.no_grad():
                baseline=net(x)[0]
                try:
                    for j in range(4):net.model[j].forward=lambda t:t
                    net.model[4].forward=lambda t:feature
                    pred=net(x)[0]
                finally:
                    for j in range(5):net.model[j].forward=forwards[j]
            if not torch.isfinite(pred).all() or not torch.isfinite(baseline).all():raise RuntimeError('Nonfinite prediction')
            det=ops.non_max_suppression(pred,.25,.45,agnostic=False)[0]
            expected=json.loads((ROOT/f'metrics/evidence/recognition/verified_results/image{i}_report.json').read_text(encoding='utf-8'))['detections']
            if [net.names[int(row[5])] for row in det.tolist()]!=[d['class_name'] for d in expected]:raise RuntimeError('Detection classes changed')
            if not np.allclose(det[:,4].numpy(),[d['confidence'] for d in expected],atol=1e-5):raise RuntimeError('Prediction scores changed')
            print(f'image{i}: packaged images/model/reference and archived FPGA result passed')
        print('Offline model/reference checks passed. No FPGA was accessed; this is not a new hardware run.')
    print(f'Integrity passed: {len(integrity)} files')
if __name__=='__main__':main()
