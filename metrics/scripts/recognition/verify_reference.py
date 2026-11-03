from pathlib import Path
import sys,json,time
import torch,numpy as np,cv2
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'host/app/recognition'))
import gui_backend as m
from project_paths import resolve_asset
torch.set_num_threads(4)
params=m.load_parameters();results=[]
for p in sorted((ROOT/'metrics/evidence/recognition/fixtures').glob('image*.npz')):
    began=time.perf_counter()
    with np.load(p) as d:
        im=cv2.imdecode(np.fromfile(str(resolve_asset(str(d['image_path']))),dtype=np.uint8),cv2.IMREAD_COLOR)
        x,xq=m.preprocess(im)
        assert np.array_equal(x,d['x']) and np.array_equal(xq,d['xq'])
        y,debug,clip=m.reference(xq,params)
        assert np.array_equal(y,d['golden']) and np.array_equal(debug,d['debug'])
        assert np.array_equal(m.packed(xq),d['words'])
        changed=xq.copy();changed[0,:,100,100]^=255
        challenge,_,_=m.reference(changed,params)
        assert np.array_equal(challenge,d['challenge'])
    results.append(dict(case=p.name,exact_values=65536,debug_values=60,challenge_passed=True,seconds=time.perf_counter()-began))
    print(results[-1],flush=True)
out=ROOT/'metrics/runs/recognition/offline_verification.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(dict(passed=True,hardware_accessed=False,cases=results),indent=2))
print('Offline verification passed. No FPGA accessed.')
