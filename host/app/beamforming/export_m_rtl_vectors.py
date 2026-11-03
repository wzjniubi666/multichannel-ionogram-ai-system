"""Explicit raw-M compression and int16 export for 32-record board frames.

No hardware traffic. The 512-record mode is algorithm-only; BFM1/1 stays 32.
"""
from pathlib import Path
import argparse
import json
import math
import numpy as np
from export_rtl_vectors import hex_file
from m_sequence_pipeline import MProfile,RawMCapture,make_chips,circular_compress,sha256
from mvdr_reference import l16_positions,steering_vector
from mvdr_fixed_reference import solve_fixed,beam_fixed


def quantize_iq(x, gain):
    if not np.isfinite(gain) or gain <= 0 or not np.isfinite(x).all():
        raise ValueError("finite positive gain and finite IQ required")
    re,im=np.rint(x.real*gain),np.rint(x.imag*gain)
    clipped=int(np.count_nonzero((re < -32768)|(re>32767)) + np.count_nonzero((im < -32768)|(im>32767)))
    return np.clip(re,-32768,32767).astype(np.int64),np.clip(im,-32768,32767).astype(np.int64),clipped


def export(folder,out,frequency=10.0,lag=80,start=0,records=32,gain=None):
    if records not in (32,512) or start<0 or start+records>512 or not 0<=lag<1020:
        raise ValueError("expected 32 or 512 consecutive records and a complete-period relative lag")
    if out.exists():
        raise FileExistsError(out)
    profile=MProfile()
    cap=RawMCapture(folder,profile)
    matches=np.flatnonzero(np.isclose(cap.frequency_mhz,frequency,atol=1e-9,rtol=0))
    if len(matches)!=1:
        raise ValueError("frequency must be a captured nominal grid point")
    fi=int(matches[0])
    code=np.repeat(make_chips(profile),4)
    raw=cap.read(fi)
    # A single requested lag needs only a direct inner product, no FFT of all lags.
    x_all=np.einsum("ckn,n->ck",raw,np.roll(code,lag).conj())/1020
    np.testing.assert_allclose(x_all[:2,:3],circular_compress(raw[:2,:3],code)[:,:,lag],atol=1e-10)
    del raw
    peak=float(max(abs(x_all.real).max(),abs(x_all.imag).max()))
    if not peak>0:
        raise ValueError("zero input cannot establish MVDR validation")
    # Shared across all 512 records at this frequency/lag and all 16 channels.
    if gain is None:
        gain=2.0**math.floor(math.log2(16383.0/peak))
    x=x_all[:,start:start+records]
    ii,qq,clipped=quantize_iq(x,gain)
    if clipped:
        raise ValueError(f"input clipping ({clipped} components); reduce the gain explicitly")
    rr=ii@ii.T+qq@qq.T
    ri=qq@ii.T-ii@qq.T
    a=steering_vector(l16_positions(10),113,35,299792458/(frequency*1e6))
    scale=1<<23
    ar=np.clip(np.rint(a.real*scale),-scale,scale-1).astype(np.int64)
    ai=np.clip(np.rint(a.imag*scale),-scale,scale-1).astype(np.int64)
    aq=(ar+1j*ai)/scale
    weights,diagnostic=solve_fixed(rr.tolist(),ri.tolist(),ar.tolist(),ai.tolist())
    beam=beam_fixed(ii.tolist(),qq.tolist(),weights)
    loaded=rr+diagnostic['loading_integer']*np.eye(16)+1j*ri
    v=np.linalg.solve(loaded,aq)
    wf=v/np.vdot(aq,v)
    wq=np.asarray([complex(r,i)/scale for r,i in weights])
    werr=float(abs(wq-wf).max())
    constraint=float(abs(np.vdot(wq,aq)-1))
    if werr>0.002 or constraint>0.005:
        raise ArithmeticError(f"fixed-point accuracy gate failed: weight={werr}, constraint={constraint}")
    float_beam=wf.conj()@(ii+1j*qq)
    fixed_beam=np.asarray([complex(r,i) for r,i in beam])
    beam_relative=float(np.linalg.norm(fixed_beam-float_beam)/max(np.linalg.norm(float_beam),1))
    if beam_relative>0.02:
        raise ArithmeticError(f"fixed vs floating beam relative error {beam_relative}>0.02")
    out.mkdir(parents=True,exist_ok=False)
    for name,data,width in [('iq_i',ii.T,16),('iq_q',qq.T,16),('cov_re',rr,48),('cov_im',ri,48),
        ('steering_re',ar,24),('steering_im',ai,24),
        ('weight_re',[w[0] for w in weights],24),('weight_im',[w[1] for w in weights],24),
        ('beam_re',[b[0] for b in beam],48),('beam_im',[b[1] for b in beam],48)]:
        hex_file(out/(name+'.hex'),data,width)
    np.savez_compressed(out/'reference.npz',compressed_iq=x,integer_iq=ii+1j*qq,
        ideal_weights=wf,fixed_weights=wq,float_beam=float_beam,fixed_beam=fixed_beam,code=code)
    report=dict(waveform='M',stage='raw full-period correlation on PC, then FPGA MVDR',
        physical_validation=False,hardware_validation=False,channels=16,snapshots=records,
        stored_records=512,record_start=start,frequency_mhz=frequency,frequency_index=fi,
        gate_index=lag,gate_semantics='relative correlation lag, not a calibrated physical range gate',
        capture_prefix=cap.prefix,profile=profile.__dict__,code_polynomial='x^8+x^4+x^3+x^2+1',
        layout_assumption='frequency,record,fast-time,IQ; >i2; protocol not verified',
        quantization=dict(gain=gain,rounding='nearest ties to even',saturation='clip to int16; reject any clipped exported frame',
            clipped_components=clipped,headroom_peak_target=16383,scale_scope='all16 channels and all512 records at this frequency/lag',
            source_peak_component=peak,max_quantization_component_error=float(max(abs(ii/gain-x.real).max(),abs(qq/gain-x.imag).max())),
            result_to_compressed_iq_scale=1/gain),
        geometry_assumption='L16 8 per arm, spacing10m, origin empty, az113/el35; mapping unverified',
        loading=0.05,loading_rule='mean=max(trunc(trace/16),1); delta=trunc(mean*5/100), matching RTL',
        fixed_model=diagnostic,fixed_float_max_weight_difference=werr,
        fixed_weight_constraint_error=constraint,fixed_float_beam_relative_l2_error=beam_relative,
        float_acceptance_limits=dict(max_weight_difference=.002,max_constraint_error=.005,beam_relative_l2=.02),
        condition_number=float(np.linalg.cond(loaded)),
        iq_order='record*16+channel',matrix_order='row*16+column',
        input_hashes=[dict(path=str(p.resolve()),sha256=sha256(p)) for p in cap.files],
        source_code_sha256={p.name:sha256(p) for p in [Path(__file__),Path(__file__).with_name('mvdr_fixed_reference.py'),
            Path(__file__).with_name('m_sequence_pipeline.py'),Path(__file__).with_name('mvdr_reference.py')]})
    if not cap.unchanged():raise RuntimeError('source changed during export')
    report['vector_sha256']={p.name:sha256(p) for p in out.glob('*.hex')}
    (out/'manifest.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    print(f"PASS M_VECTOR_EXPORT: {frequency}MHz lag{lag} records{start}..{start+records-1}, gain={gain}, weight_error={werr:.3g}, beam_error={beam_relative:.3g}")
    return report


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder',type=Path);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--frequency-mhz',type=float,default=10);p.add_argument('--lag',type=int,default=80)
    p.add_argument('--record-start',type=int,default=0);p.add_argument('--records',type=int,default=32)
    p.add_argument('--gain',type=float)
    a=p.parse_args();export(a.folder,a.output,a.frequency_mhz,a.lag,a.record_start,a.records,a.gain)
