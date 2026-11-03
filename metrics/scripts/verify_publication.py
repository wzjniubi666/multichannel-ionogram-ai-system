"""Public-source checks. Default needs only Python; --numerics replays included IQ."""
from pathlib import Path
import argparse,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[2]

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest().upper()

def main():
    p=argparse.ArgumentParser();p.add_argument('--numerics',action='store_true');a=p.parse_args()
    manifest=json.loads((ROOT/'report/package_manifest.json').read_text(encoding='utf-8'))
    for row in manifest['files']:
        path=ROOT/row['path']
        if path.stat().st_size!=row['bytes'] or sha(path)!=row['sha256']:raise ValueError('Integrity mismatch: '+row['path'])
    print('PASS public-source integrity:',len(manifest['files']),'files')
    if not a.numerics:return
    import numpy as np
    sys.path.insert(0,str(ROOT/'host/app/beamforming'))
    from mvdr_fixed_reference import solve_fixed,beam_fixed
    plan=ROOT/'metrics/evidence/beamforming/active14_smoke_plan'
    iq=np.load(plan/'iq.npy');weights=np.load(plan/'expected_weights.npy');expected=np.load(plan/'expected_beam.npy')
    steering=np.load(plan/'steering.npy');gains=np.load(plan/'gains.npy')
    for ordinal in range(len(iq)):
        fp=ordinal//gains.shape[1];ii=iq[ordinal,:,:,0].astype(np.int64).T;qq=iq[ordinal,:,:,1].astype(np.int64).T
        rr=ii@ii.T+qq@qq.T;ri=qq@ii.T-ii@qq.T
        w,_=solve_fixed(rr.tolist(),ri.tolist(),steering[fp,:,0].tolist(),steering[fp,:,1].tolist(),active_mask=0x7f7f)
        np.testing.assert_array_equal(w,weights[ordinal]);np.testing.assert_array_equal(beam_fixed(ii.tolist(),qq.tolist(),w),expected[ordinal])
    for i,path in enumerate(sorted((ROOT/'metrics/evidence/recognition/fixtures').glob('image*.npz'))):
        with np.load(path) as data:np.testing.assert_array_equal(data['golden'],np.load(ROOT/f'metrics/evidence/recognition/verified_results/image{i}_fpga_int16.npy'))
    print('PASS nine ACTIVE14 frames and three archived recognition features; no new hardware/inference run.')
if __name__=='__main__':main()
