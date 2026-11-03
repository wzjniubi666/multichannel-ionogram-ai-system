"""Immutable M32 frequency/lag scan plans; no network operations."""
from pathlib import Path
from contextlib import nullcontext
import argparse
import json
import math
import time
import numpy as np
from m_sequence_pipeline import MProfile,RawMCapture,make_chips,circular_compress,sha256
from export_m_rtl_vectors import quantize_iq
from mvdr_reference import l16_positions,steering_vector
from mvdr_fixed_reference import solve_fixed,beam_fixed
from m_board_bundle import verify_released_image

ROOT=Path(__file__).resolve().parents[1]


def integers(spec):
    if ':' in spec:
        p=list(map(int,spec.split(':')))
        if len(p)!=3 or p[2]<=0:raise ValueError('use start:stop:positive_step')
        values=list(range(*p))
    else:values=list(map(int,spec.split(',')))
    if not values or values!=sorted(set(values)):raise ValueError('coordinates must be nonempty, unique and ascending')
    return values


def prepare(folder,out,frequencies=None,lags=None,starts=None):
    folder=Path(folder).resolve();out=Path(out).resolve()
    if out.exists():raise FileExistsError(out)
    lags=lags if lags is not None else list(range(0,469,4))
    starts=starts if starts is not None else [0]
    if (not lags or lags!=sorted(set(lags)) or min(lags)<0 or max(lags)>1019
            or not starts or starts!=sorted(set(starts)) or any(s<0 or s+32>512 or s%32 for s in starts)):
        raise ValueError('ascending lags0..1019 and nonoverlapping aligned 32-record blocks within0..511 required')
    cap=RawMCapture(folder,MProfile())
    if frequencies is None:indices=list(range(len(cap.frequency_mhz)))
    else:
        indices=[]
        for f in frequencies:
            match=np.flatnonzero(np.isclose(cap.frequency_mhz,f,atol=1e-9,rtol=0))
            if len(match)!=1:raise ValueError('requested frequency is not captured')
            indices.append(int(match[0]))
        if indices!=sorted(set(indices)):raise ValueError('frequencies must be ascending and unique')
    nf,nl,nb=len(indices),len(lags),len(starts)
    count=nf*nl*nb
    if not nf or count>=1<<30:raise ValueError('invalid scan size')
    image=verify_released_image(ROOT)
    code=np.repeat(make_chips(cap.profile),4)
    out.mkdir(parents=True)
    (out/'preparing.json').write_text(json.dumps(dict(status='PREPARING_NOT_RUNNABLE',frames=count)),encoding='utf-8')
    iq=np.lib.format.open_memmap(out/'iq.npy',mode='w+',dtype=np.int16,shape=(count,32,16,2))
    beam=np.lib.format.open_memmap(out/'expected_beam.npy',mode='w+',dtype=np.int64,shape=(count,32,2))
    weights=np.lib.format.open_memmap(out/'expected_weights.npy',mode='w+',dtype=np.int32,shape=(count,16,2))
    gains=np.empty((nf,nl),float)
    steering=np.empty((nf,16,2),np.int32)
    quality=np.empty((count,3),float)
    t0=time.perf_counter()
    try:
        from threadpoolctl import threadpool_limits
        context=threadpool_limits(limits=2)
    except ImportError:
        context=nullcontext()
    with context:
        for fp,fi in enumerate(indices):
            raw=cap.read(fi)
            compressed=circular_compress(raw,code)
            del raw
            a=steering_vector(l16_positions(10),113,35,299792458/(cap.frequency_mhz[fi]*1e6))
            ar=np.clip(np.rint(a.real*(1<<23)),-(1<<23),(1<<23)-1).astype(np.int64)
            ai=np.clip(np.rint(a.imag*(1<<23)),-(1<<23),(1<<23)-1).astype(np.int64)
            steering[fp,:,0]=ar;steering[fp,:,1]=ai
            aq=(ar+1j*ai)/(1<<23)
            for lp,lag in enumerate(lags):
                x=compressed[:,:,lag]
                peak=float(max(abs(x.real).max(),abs(x.imag).max()))
                if peak==0:raise ValueError('all-zero candidate lag cannot establish MVDR')
                gain=2.0**math.floor(math.log2(16383/peak));gains[fp,lp]=gain
                for bp,start in enumerate(starts):
                    ordinal=(fp*nl+lp)*nb+bp
                    ii,qq,clipped=quantize_iq(x[:,start:start+32],gain)
                    if clipped:raise ValueError('quantization clipped')
                    rr=ii@ii.T+qq@qq.T;ri=qq@ii.T-ii@qq.T
                    w,info=solve_fixed(rr.tolist(),ri.tolist(),ar.tolist(),ai.tolist())
                    b=beam_fixed(ii.tolist(),qq.tolist(),w)
                    v=np.linalg.solve(rr+np.eye(16)*info['loading_integer']+1j*ri,aq)
                    wf=v/np.vdot(aq,v);wq=np.asarray([complex(r,i)/(1<<23) for r,i in w])
                    ideal=wf.conj()@(ii+1j*qq)
                    actual=np.asarray([complex(r,i) for r,i in b])
                    err=float(abs(wq-wf).max());constraint=float(abs(np.vdot(wq,aq)-1))
                    relative=float(np.linalg.norm(actual-ideal)/max(np.linalg.norm(ideal),1))
                    if err>.002 or constraint>.005:
                        (out/'preparation_failure.json').write_text(json.dumps(dict(
                            ordinal=ordinal,frequency_mhz=float(cap.frequency_mhz[fi]),lag=lag,
                            weight_error=err,constraint_error=constraint)),encoding='utf-8')
                        raise ArithmeticError('fixed-point weight/constraint quality gate failed; plan remains unready')
                    iq[ordinal,:,:,0]=ii.T;iq[ordinal,:,:,1]=qq.T
                    beam[ordinal]=b;weights[ordinal]=w;quality[ordinal]=(err,constraint,relative)
            del compressed
            iq.flush();beam.flush();weights.flush()
            print(f'PREPARE {fp+1}/{nf}: {cap.frequency_mhz[fi]:g}MHz, {(fp+1)*nl*nb}/{count} frames',flush=True)
    np.save(out/'gains.npy',gains);np.save(out/'steering.npy',steering);np.save(out/'quality.npy',quality)
    iq.flush();beam.flush();weights.flush()
    source=[dict(path=str(p),sha256=sha256(p),bytes=p.stat().st_size) for p in cap.files]
    if not cap.unchanged():raise RuntimeError('raw source changed during preparation')
    manifest=dict(version=1,status='READY_OFFLINE_PLAN',waveform='M',records_per_frame=32,channels=16,
        capture_prefix=cap.prefix,capture_directory=str(folder),source=source,
        frequency_mhz=cap.frequency_mhz[indices].tolist(),source_frequency_index=indices,
        relative_lag_samples=lags,record_starts=starts,frames=count,profile=cap.profile.__dict__,
        code_polynomial='x^8+x^4+x^3+x^2+1',initial_state='11111111',
        layout='frequency,record,fast-time,IQ >i2; provisional',
        geometry='L16 8+8 arms 10m, origin empty, az113/el35; unverified mapping',
        quantization='gain shared over all512 records/channels per frequency/lag; power-of-two, target16383; nearest ties-even; no clipping',
        frame_order='((frequency_position * lag_count) + lag_position) * block_count + block_position',
        integration='mean squared magnitude of all verified rescaled outputs; independent MVDR weights per32-record block',
        physical_parameters_verified=False,hardware_scan_executed=False,
        fixed_model_quality=dict(max_weight_error=float(quality[:,0].max()),max_constraint_error=float(quality[:,1].max()),
            beam_relative_l2_range=[float(quality[:,2].min()),float(quality[:,2].max())],
            beam_relative_l2_over_2percent=int(np.count_nonzero(quality[:,2]>.02)),
            note='beam relative error is reported; weak output can be dominated by final integer rounding; not an SNR metric'),
        image_binding=image,elapsed_seconds=time.perf_counter()-t0,
        source_code_sha256={name:sha256(Path(__file__).with_name(name)) for name in (
            'm_batch_plan.py','mvdr_fixed_reference.py','m_sequence_pipeline.py','mvdr_reference.py','export_m_rtl_vectors.py')},
        file_sha256={p.name:sha256(p) for p in out.glob('*.npy')})
    (out/'plan.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'PASS SCAN_PLAN: {nf} frequencies x {nl} lags x {nb} blocks = {count} frames; no traffic')
    return manifest


class ScanPlan:
    def __init__(self,path,verify=True):
        self.path=Path(path).resolve()
        self.meta=json.loads((self.path/'plan.json').read_text(encoding='utf-8'))
        m=self.meta
        if (m['version'],m['status'],m['records_per_frame'],m['channels'])!=(1,'READY_OFFLINE_PLAN',32,16):
            raise ValueError('unsupported/unready scan plan')
        self.hash=sha256(self.path/'plan.json')
        self.nf=len(m['frequency_mhz']);self.nl=len(m['relative_lag_samples']);self.nb=len(m['record_starts'])
        if self.nf*self.nl*self.nb!=m['frames']:raise ValueError('plan count mismatch')
        if verify:
            for name,expected in m['file_sha256'].items():
                if sha256(self.path/name)!=expected:raise ValueError('prepared file changed: '+name)
            for name,expected in m['source_code_sha256'].items():
                if sha256(Path(__file__).with_name(name))!=expected:raise ValueError('preparation/model source changed: '+name)
            verify_released_image(ROOT)
        self.iq=np.load(self.path/'iq.npy',mmap_mode='r')
        self.expected=np.load(self.path/'expected_beam.npy',mmap_mode='r')
        self.weights=np.load(self.path/'expected_weights.npy',mmap_mode='r')
        self.gains=np.load(self.path/'gains.npy',mmap_mode='r')
        self.steering=np.load(self.path/'steering.npy',mmap_mode='r')
        if self.iq.shape!=(m['frames'],32,16,2) or self.expected.shape!=(m['frames'],32,2):
            raise ValueError('prepared array shape mismatch')

    def coordinate(self,ordinal):
        if not 0<=ordinal<self.meta['frames']:raise IndexError(ordinal)
        fp,rem=divmod(ordinal,self.nl*self.nb);lp,bp=divmod(rem,self.nb)
        return fp,lp,bp


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder',type=Path);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--frequencies',help='comma-separated nominal MHz, omitted means all captured frequencies')
    p.add_argument('--lags',default='0:469:4',help='start:stop_exclusive:step or comma-separated samples')
    p.add_argument('--record-starts',default='0',help='aligned 32-record block starts;0..480')
    a=p.parse_args();prepare(a.folder,a.output,list(map(float,a.frequencies.split(','))) if a.frequencies else None,
                           integers(a.lags),integers(a.record_starts))
