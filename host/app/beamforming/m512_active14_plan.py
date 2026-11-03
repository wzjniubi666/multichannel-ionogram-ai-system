"""Active14 actual-code512 plans;16-lane transport, az113/el35; no hardware traffic."""
from pathlib import Path
from contextlib import nullcontext
import argparse
import json
import math
import shutil
import time
import numpy as np
from m_sequence_pipeline import MProfile,RawMCapture,sha256
from m_batch_plan import integers
from m_reference_preprocess import METHOD,load_reference,compress_periods,verify_frequency
from export_m_rtl_vectors import quantize_iq
from mvdr_reference import l16_positions,steering_vector
from mvdr_fixed_reference import solve_fixed,beam_fixed
# Image identity is checked by the active14 release gate before any hardware traffic.

ROOT=Path(__file__).resolve().parents[1]


def prepare(folder,out,reference,frequencies=None,lags=None,starts=None):
    folder,out,reference=map(lambda p:Path(p).resolve(),(folder,out,reference))
    if out.exists():raise FileExistsError(out)
    lags=lags if lags is not None else list(range(0,469,4))
    starts=starts if starts is not None else [0]
    if (not lags or lags!=sorted(set(lags)) or min(lags)<0 or max(lags)>1019
            or not starts or starts!=sorted(set(starts)) or starts!=[0]):
        raise ValueError('ascending lags0..1019 and aligned nonoverlapping 32-period blocks required')
    cap=RawMCapture(folder,MProfile())
    indices=list(range(len(cap.frequency_mhz))) if frequencies is None else []
    for frequency in frequencies or []:
        matches=np.flatnonzero(np.isclose(cap.frequency_mhz,frequency,atol=1e-9,rtol=0))
        if len(matches)!=1:raise ValueError('frequency not on captured grid')
        indices.append(int(matches[0]))
    if not indices or indices!=sorted(set(indices)):raise ValueError('ascending distinct frequencies required')
    original_reference={name:sha256(reference/name) for name in ('m255a.mat','readone.m','readall.m')}
    code=load_reference(reference/'m255a.mat')
    nf,nl,nb=len(indices),len(lags),len(starts);count=nf*nl*nb
    active_mask=0x7f7f
    keep=[i for i in range(16) if active_mask & (1<<i)]
    image=dict(active_mask=active_mask,profile="ACTIVE14",hardware_bound_at_execution=True)
    out.mkdir(parents=True)
    (out/'preparing.json').write_text(json.dumps(dict(status='PREPARING_NOT_RUNNABLE',frames=count)),encoding='utf-8')
    snapshot=out/'reference_snapshot';snapshot.mkdir()
    for name in original_reference:shutil.copy2(reference/name,snapshot/name)
    np.save(out/'reference_code.npy',code)
    iq=np.lib.format.open_memmap(out/'iq.npy',mode='w+',dtype=np.int16,shape=(count,512,16,2))
    beam=np.lib.format.open_memmap(out/'expected_beam.npy',mode='w+',dtype=np.int64,shape=(count,512,2))
    weights=np.lib.format.open_memmap(out/'expected_weights.npy',mode='w+',dtype=np.int32,shape=(count,16,2))
    gains=np.empty((nf,nl),float);steering=np.empty((nf,16,2),np.int32);quality=np.empty((count,3),float)
    checks=[];t0=time.perf_counter()
    try:
        from threadpoolctl import threadpool_limits
        context=threadpool_limits(limits=2)
    except ImportError:context=nullcontext()
    with context:
        for fp,fi in enumerate(indices):
            raw=cap.read(fi)
            compressed=compress_periods(raw,code)
            checks.append(dict(frequency_mhz=float(cap.frequency_mhz[fi]),**verify_frequency(raw,compressed,code)))
            del raw
            a=steering_vector(l16_positions(10),113,35,299792458/(cap.frequency_mhz[fi]*1e6))
            ar=np.clip(np.rint(a.real*(1<<23)),-(1<<23),(1<<23)-1).astype(np.int64)
            ai=np.clip(np.rint(a.imag*(1<<23)),-(1<<23),(1<<23)-1).astype(np.int64)
            steering[fp,:,0]=ar;steering[fp,:,1]=ai;aq=(ar+1j*ai)/(1<<23)
            for lp,lag in enumerate(lags):
                x=compressed[:,:,lag]
                peak=float(max(abs(x.real).max(),abs(x.imag).max()))
                if not peak>0:raise ValueError('zero compressed IQ')
                gain=2.0**math.floor(math.log2(16383/peak));gains[fp,lp]=gain
                for bp,start in enumerate(starts):
                    ordinal=(fp*nl+lp)*nb+bp
                    ii,qq,clipped=quantize_iq(x[:,start:start+512],gain)
                    if clipped:raise ValueError('input quantization clipped')
                    rr=ii@ii.T+qq@qq.T;ri=qq@ii.T-ii@qq.T
                    w,info=solve_fixed(rr.tolist(),ri.tolist(),ar.tolist(),ai.tolist(),active_mask=active_mask)
                    b=beam_fixed(ii.tolist(),qq.tolist(),w)
                    r14=(rr+1j*ri)[np.ix_(keep,keep)]+np.eye(14)*info['loading_integer']
                    v=np.linalg.solve(r14,aq[keep]);wf=np.zeros(16,complex)
                    wf[keep]=v/np.vdot(aq[keep],v);wq=np.asarray([complex(r,i)/(1<<23) for r,i in w])
                    ideal=wf.conj()@(ii+1j*qq);actual=np.asarray([complex(r,i) for r,i in b])
                    err=float(abs(wq-wf).max());constraint=float(abs(np.vdot(wq,aq)-1))
                    relative=float(np.linalg.norm(actual-ideal)/max(np.linalg.norm(ideal),1))
                    if err>.002 or constraint>.005:
                        (out/'preparation_failure.json').write_text(json.dumps(dict(ordinal=ordinal,
                            frequency_mhz=float(cap.frequency_mhz[fi]),lag=lag,weight_error=err,constraint_error=constraint)),encoding='utf-8')
                        raise ArithmeticError('fixed-point weight/constraint quality gate failed')
                    iq[ordinal,:,:,0]=ii.T;iq[ordinal,:,:,1]=qq.T
                    beam[ordinal]=b;weights[ordinal]=w;quality[ordinal]=(err,constraint,relative)
            del compressed
            iq.flush();beam.flush();weights.flush()
            print(f'PREPARE HF {fp+1}/{nf}: {cap.frequency_mhz[fi]:g}MHz {(fp+1)*nl*nb}/{count}',flush=True)
    for name,data in (('gains',gains),('steering',steering),('quality',quality)):np.save(out/(name+'.npy'),data)
    iq.flush();beam.flush();weights.flush()
    sources=[dict(path=str(f),sha256=sha256(f),bytes=f.stat().st_size) for f in cap.files]
    if not cap.unchanged() or original_reference!={name:sha256(reference/name) for name in original_reference}:
        raise RuntimeError('input or reference changed')
    (out/'preprocess_checks.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
    names=('m512_active14_plan.py','m_reference_preprocess.py','m_batch_plan.py','mvdr_fixed_reference.py',
        'm_sequence_pipeline.py','mvdr_reference.py','export_m_rtl_vectors.py')
    manifest=dict(version=1,status='READY_OFFLINE_PLAN',waveform='M',records_per_frame=512,channels=16,
        active_channel_mask=0x7f7f,active_channels=14,excluded_channels=[7,15],
        preprocessing=METHOD,capture_prefix=cap.prefix,capture_directory=str(folder),source=sources,
        frequency_mhz=cap.frequency_mhz[indices].tolist(),source_frequency_index=indices,
        relative_lag_samples=lags,record_starts=starts,frames=count,profile=cap.profile.__dict__,
        reference_files_sha256=original_reference,reference_directory=str(reference),
        correlation='per-period four phases independently correlated with actual255 chips; lag=4*chip_lag+phase; unnormalized sum255',
        period_accumulation_before_fpga=False,
        layout='frequency,period,chip,sample_phase,IQ; >i2; consistent with supplied reference indexing',
        geometry='L16 8+8 arms 10m, origin empty, az113/el35; still unverified mapping',
        range_axis=dict(convention='HF_reference_script',step_km=7.68,index_offset=1,calibrated=False),
        quantization='gain shared over16 channels and512 periods per frequency/lag; power of two; target16383; nearest ties-even; reject clipping',
        frame_order='((frequency_position*lag_count)+lag_position)*block_count+block_position',
        algorithm='MVDR_JOINT512',
        integration='primary abs(sum_512_verified_complex_outputs/gain)^2; secondary mean output power; one shared MVDR weight set over512 periods',
        physical_parameters_verified=False,hardware_scan_executed=False,loading=.05,
        fixed_model_quality=dict(max_weight_error=float(quality[:,0].max()),max_constraint_error=float(quality[:,1].max()),
            beam_relative_l2_range=[float(quality[:,2].min()),float(quality[:,2].max())],
            beam_relative_l2_over_2percent=int(np.count_nonzero(quality[:,2]>.02)),
            note='reported diagnostic, not SNR; weak outputs are sensitive to integer rounding'),
        active14_profile=image,elapsed_seconds=time.perf_counter()-t0,
        source_code_sha256={name:sha256(Path(__file__).with_name(name)) for name in names},
        file_sha256={str(f.relative_to(out)):sha256(f) for f in out.rglob('*') if f.is_file() and f.name!='preparing.json'})
    (out/'plan.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'PASS HF_M512_PLAN: {count} frames; actual code/phase correlation; no hardware traffic')
    return manifest


class Plan512:
    def __init__(self,path,verify=True):
        self.path=Path(path).resolve()
        self.meta=json.loads((self.path/'plan.json').read_text(encoding='utf-8'))
        m=self.meta
        if (m['version'],m['status'],m['records_per_frame'],m['channels'])!=(1,'READY_OFFLINE_PLAN',512,16):
            raise ValueError('joint512 plan required')
        if m.get('preprocessing')!=METHOD or m.get('algorithm')!='MVDR_JOINT512' or m['record_starts']!=[0]:
            raise ValueError('actual-reference512 joint processing required')
        if m.get('active_channel_mask')!=0x7f7f or m.get('active_channels')!=14:
            raise ValueError('active14 plan with channels07/15 excluded required')
        self.hash=sha256(self.path/'plan.json')
        self.nf=len(m['frequency_mhz']);self.nl=len(m['relative_lag_samples']);self.nb=1
        if self.nf*self.nl!=m['frames']:raise ValueError('512 coordinate count mismatch')
        if verify:
            for name,wanted in m['source_code_sha256'].items():
                if sha256(Path(__file__).with_name(name))!=wanted:raise ValueError('512 preparation source changed: '+name)
            for name,wanted in m['file_sha256'].items():
                if sha256(self.path/name)!=wanted:raise ValueError('512 prepared data changed: '+name)
            np.testing.assert_array_equal(load_reference(self.path/'reference_snapshot/m255a.mat'),np.load(self.path/'reference_code.npy'))
        for attr,file in (('iq','iq.npy'),('expected','expected_beam.npy'),('weights','expected_weights.npy'),('gains','gains.npy'),('steering','steering.npy')):
            setattr(self,attr,np.load(self.path/file,mmap_mode='r'))
        if self.iq.shape!=(m['frames'],512,16,2) or self.expected.shape!=(m['frames'],512,2):
            raise ValueError('512 array shape mismatch')

    def coordinate(self,ordinal):
        if not 0<=ordinal<self.meta['frames']:raise IndexError(ordinal)
        fp,lp=divmod(ordinal,self.nl)
        return fp,lp,0


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder',type=Path);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--reference',type=Path,required=True);p.add_argument('--frequencies')
    p.add_argument('--lags',default='0:469:4')
    a=p.parse_args();prepare(a.folder,a.output,a.reference,
        list(map(float,a.frequencies.split(','))) if a.frequencies else None,integers(a.lags),[0])

