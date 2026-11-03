"""Live display values derived only from committed, verified FPGA transactions."""
from pathlib import Path
import numpy as np


def metadata(plan, output, mode):
    return dict(path=str(Path(output).resolve()), source=mode, plan_sha256=plan.hash,
                capture=Path(plan.meta['capture_directory']).name,
                frequency_mhz=plan.meta['frequency_mhz'],
                source_frequency_index=plan.meta['source_frequency_index'],
                relative_lag_samples=plan.meta['relative_lag_samples'], total=plan.meta['frames'])


def committed_pixel(plan, ordinal, packets):
    from udp512 import beam_values
    values=[pair for packet in packets for pair in beam_values(packet)]
    if len(values)!=512:
        raise ValueError('Live preview requires a complete, verified 512-record frame')
    fp,lp,_=plan.coordinate(ordinal)
    gain=float(plan.gains[fp,lp])
    actual=np.asarray(values,dtype=np.float64)/gain
    sr,si=actual[:,0].sum(),actual[:,1].sum()
    iq=plan.iq[ordinal,:,0,:].astype(np.int64)
    single=iq[:,0].sum()/gain,iq[:,1].sum()/gain
    return dict(ordinal=int(ordinal),fp=int(fp),lp=int(lp),
                board=float(sr*sr+si*si),single=float(single[0]**2+single[1]**2))


def create_data(meta):
    from backend import ResultData
    if meta['source'] not in ('hardware','emulator'):
        raise ValueError('Unknown live preview source')
    frequencies=np.asarray(meta['frequency_mhz'],dtype=float)
    lags=np.asarray(meta['relative_lag_samples'],dtype=int)
    shape=(len(frequencies),len(lags))
    if shape[0]*shape[1]!=meta['total']:
        raise ValueError('Live preview grid mismatch')
    return ResultData(Path(meta['path']),dict(source=meta['source'],status='RUNNING_'+meta['source'].upper(),
        verified_frames=0,planned_frames=meta['total'],plan_sha256=meta['plan_sha256'],live_preview=True),
        frequencies,(lags+1)*7.68,np.full(shape,np.nan),np.full(shape,np.nan),np.zeros(shape,bool),
        meta['capture'],np.asarray(meta['source_frequency_index'],dtype=int),lags)


def apply_pixel(data, pixel):
    fp,lp=int(pixel['fp']),int(pixel['lp'])
    if not (0<=fp<data.complete.shape[0] and 0<=lp<data.complete.shape[1]):
        raise ValueError('Live preview coordinate outside plan')
    if int(pixel['ordinal'])!=fp*data.complete.shape[1]+lp:
        raise ValueError('Live preview frame/coordinate mismatch')
    values=float(pixel['board']),float(pixel['single'])
    if not all(np.isfinite(v) and v>=0 for v in values):
        raise ValueError('Invalid live preview power')
    data.board[fp,lp],data.single[fp,lp]=values
    data.complete[fp,lp]=True
    data.summary['verified_frames']=int(data.complete.sum())


def relay_process(command):
    """Give the PowerShell grandchild explicit pipes on Windows, then flush each event."""
    import subprocess
    with subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                          text=True,encoding='utf-8',errors='replace',bufsize=1,
                          creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)) as process:
        for line in process.stdout:
            print(line,end='',flush=True)
        return process.wait()
