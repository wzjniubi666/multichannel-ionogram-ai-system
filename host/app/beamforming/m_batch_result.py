"""Audit persisted packets and aggregate only verified scan measurements."""
from pathlib import Path
import csv
import json
import numpy as np
from udp_replay import decode,beam_values,Packet,ACK


def audit_rows(db,plan):
    from m_batch_scan import requests
    rows=list(db.execute('SELECT r.ordinal AS accepted_ordinal,a.* FROM results r JOIN attempts a ON a.id=r.attempt_id ORDER BY r.ordinal'))
    seen=set()
    for row in rows:
        ordinal=row['ordinal']
        if ordinal!=row['accepted_ordinal'] or ordinal in seen or row['status']!='VERIFIED' or row['sent_count']!=3:
            raise ValueError('journal ownership/status mismatch')
        seen.add(ordinal)
        cfg,iq,expected=requests(plan,ordinal,row['nonce'])
        if (row['config_id'],row['frame_id'])!=(cfg.config_id,expected.frame_id):raise ValueError('journal identity mismatch')
        for key,value in [('planned_config',cfg.encode()),('planned_iq0',iq[0].encode()),('planned_iq1',iq[1].encode()),
            ('received_1',Packet(ACK,0,cfg.config_id,cfg.frequency_index,cfg.gate_index).encode()),('received_2',expected.encode())]:
            if row[key]!=value:raise ValueError('journal packet mismatch: '+key)
    return rows


def aggregate(db,plan,output,mode,render=True,run_error=None):
    output=Path(output)
    rows=audit_rows(db,plan)
    shape=(plan.nf,plan.nl,plan.nb,32)
    real=np.full(shape,np.nan);imag=np.full(shape,np.nan)
    mask=np.zeros(shape[:3],bool)
    quality_path=plan.path/'quality.npy'
    quality=np.load(quality_path) if quality_path.exists() else np.full((plan.meta['frames'],3),np.nan)
    with (output/'beam_records.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['frequency_mhz','relative_lag_samples','record_index','frame_id',
            'I_raw_int48','Q_raw_int48','gain','I_rescaled','Q_rescaled','source'])
        for row in rows:
            fp,lp,bp=plan.coordinate(row['ordinal']);gain=float(plan.gains[fp,lp])
            values=beam_values(decode(row['received_2']))
            for k,(r,i) in enumerate(values):
                real[fp,lp,bp,k]=r/gain;imag[fp,lp,bp,k]=i/gain
                writer.writerow([plan.meta['frequency_mhz'][fp],plan.meta['relative_lag_samples'][lp],
                    plan.meta['record_starts'][bp]+k,f'0x{row["frame_id"]:08X}',r,i,gain,r/gain,i/gain,mode])
            mask[fp,lp,bp]=True
    pixel_complete=mask.all(axis=2)
    power=np.mean(real*real+imag*imag,axis=(2,3))
    power[~pixel_complete]=np.nan
    distance=np.asarray(plan.meta['relative_lag_samples'])*299792458*plan.meta['profile']['sample_period_us']*1e-6/2000
    np.savez_compressed(output/'scan_results.npz',frequency_mhz=plan.meta['frequency_mhz'],
        relative_lag_samples=plan.meta['relative_lag_samples'],relative_group_range_km=distance,
        record_starts=plan.meta['record_starts'],beam_re_rescaled=real,beam_im_rescaled=imag,
        frame_verified=mask,pixel_complete=pixel_complete,power=power,source=mode)
    with (output/'ionogram_power.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['frequency_mhz','relative_lag_samples','relative_group_range_km',
            'verified_blocks','required_blocks','mean_beam_power','prepared_model_max_beam_relative_l2_error','source'])
        for fp,freq in enumerate(plan.meta['frequency_mhz']):
            for lp,lag in enumerate(plan.meta['relative_lag_samples']):
                writer.writerow([freq,lag,distance[lp],int(mask[fp,lp].sum()),plan.nb,
                    float(power[fp,lp]) if pixel_complete[fp,lp] else '',
                    float(quality[(fp*plan.nl+lp)*plan.nb:(fp*plan.nl+lp+1)*plan.nb,2].max()),mode])
    complete=len(rows)==plan.meta['frames']
    summary=dict(status=('COMPLETE_' if complete else 'PARTIAL_')+mode.upper(),source=mode,
        hardware_measurements=(mode=='hardware'),plan_sha256=plan.hash,plan_directory=str(plan.path),
        planned_frames=plan.meta['frames'],verified_frames=len(rows),complete_pixels=int(pixel_complete.sum()),
        planned_pixels=plan.nf*plan.nl,record_starts=plan.meta['record_starts'],records_per_frame=32,
        attempts=int(db.execute('SELECT count(*) FROM attempts').fetchone()[0]),run_error=run_error,
        missing_data='NaN/empty CSV/grey pixels; no reference values substituted',
        integration='mean(abs(beam/gain)**2) across all32 outputs and all planned verified blocks per pixel',
        joint_512_record_weights=False,physical_parameters_verified=False,
        range_conversion='relative lag * 25.6us * c/2, provisional two-way convention; zero not calibrated',
        raw_packets='scan.sqlite3 attempts table: planned packets, received ACK and RESULT, IDs and statuses',
        no_automatic_retry=True)
    summary['prepared_numerical_quality']=plan.meta.get('fixed_model_quality',{})
    if plan.meta.get('preprocessing')=='HF_M255_PHASE4_PER_PERIOD_V1':
        from m_reference_result import finalize
        return finalize(plan,output,real,imag,mask,summary,render)
    if render:summary['plot']=plot(output,plan,power,distance,mode,len(rows))
    (output/'scan_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    (output/'说明.txt').write_text(
        f"来源：{mode}（hardware=实板回包，emulator=协议自测、不是实板）\n"
        f"已逐字节验证{len(rows)}/{plan.meta['frames']}帧；每帧16通道×32记录，独立MVDR权值。\n"
        "beam_records.csv为已验证的逐条复数波束输出；ionogram_power.csv及scan_results.npz为频率×相对延迟功率矩阵。\n"
        "原始计划输入、ACK/RESULT、错误及中断记录保存在scan.sqlite3；通过该数据库可明确断点续传。\n"
        "未完成像素留空/NaN/灰色，不以参考模型补填；功率按每帧实际量化增益还原后计算，非物理瓦特或SNR。\n"
        "每个位置若选择多个32记录块，则对各块输出功率再平均；仍不是512记录联合求权。\n"
        "距离按暂定25.6微秒采样和双程cτ/2换算，M码、数据排列和阵列映射仍待物理核实。\n",encoding='utf-8-sig')
    return summary


def plot(output,plan,power,distance,mode,verified):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    font_manager.fontManager.addfont('C:/Windows/Fonts/msyh.ttc')
    font=font_manager.FontProperties(fname='C:/Windows/Fonts/msyh.ttc').get_name()
    valid=np.isfinite(power)
    reference=float(power[valid].max()) if valid.any() and power[valid].max()>0 else 1.
    data=10*np.log10(np.maximum(power,1e-12)/reference)
    lo=float(data[valid].min()) if valid.any() else -1.
    hi=float(data[valid].max()) if valid.any() else 0.
    if hi<=lo:lo=hi-1
    def edges(a,step):
        a=np.asarray(a,float)
        return np.r_[a[0]-(a[1]-a[0])/2,(a[:-1]+a[1:])/2,a[-1]+(a[-1]-a[-2])/2] if len(a)>1 else np.array([a[0]-step/2,a[0]+step/2])
    # Sparse diagnostics must show unscanned frequencies/lags as missing,
    # rather than spreading three observations over large midpoint cells.
    frequencies=np.asarray(plan.meta['frequency_mhz'],float)
    indices=np.asarray(plan.meta['source_frequency_index'],int)
    fstep=(frequencies[-1]-frequencies[0])/(indices[-1]-indices[0]) if len(indices)>1 else .5
    source_lags=np.asarray(plan.meta['relative_lag_samples'],int)
    lag_step=min(4,int(np.gcd.reduce(np.diff(source_lags)))) if len(source_lags)>1 else 4
    dense_frequency=np.arange(indices[0],indices[-1]+1)*fstep+(frequencies[0]-indices[0]*fstep)
    dense_lag=np.arange(source_lags[0],source_lags[-1]+1,lag_step)
    dense_distance=dense_lag*299792458*plan.meta['profile']['sample_period_us']*1e-6/2000
    display=np.full((len(dense_frequency),len(dense_lag)),np.nan)
    display[np.ix_(indices-indices[0],(source_lags-source_lags[0])//lag_step)]=data
    cmap=plt.get_cmap('cividis').copy();cmap.set_bad('#bbbbbb')
    label='实板回包' if mode=='hardware' else '协议仿真（非实板）'
    with plt.rc_context({'font.family':font,'font.size':12,'axes.unicode_minus':False}):
        fig,ax=plt.subplots(figsize=(9,7),layout='constrained')
        mesh=ax.pcolormesh(edges(dense_frequency,fstep),edges(dense_distance,15.35),
            np.ma.masked_invalid(display.T),cmap=cmap,vmin=lo,vmax=hi,shading='flat',rasterized=True)
        ax.set(xlabel='名义频率（MHz）',ylabel='相对群距离（km）',
            title=f'M序列MVDR批量电离图 · {label}\n已验证{verified}/{plan.meta["frames"]}帧')
        ax.set_ylim(bottom=0)
        fig.colorbar(mesh,ax=ax,label='相对功率（dB，已完成像素共同参考）')
        fig.text(.5,.012,'灰色为未扫描/未完成；32条/帧独立求权、功率平均；无插值或平滑。\n'
            '距离暂按双程cτ/2；码/布局/阵列及零点待核实；颜色不代表已校准SNR。',ha='center',va='bottom',fontsize=9)
        fig.get_layout_engine().set(rect=(0,.09,1,.91))
        fig.savefig(output/'ionogram.png',dpi=180,facecolor='white')
        plt.close(fig)
    return dict(common_db_limits=[lo,hi],reference_power=reference,power_floor=1e-12,
        interpolation=False,smoothing=False,missing_colour='#bbbbbb',unscanned_gaps_retained=True)
