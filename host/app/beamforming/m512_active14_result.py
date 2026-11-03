"""Aggregate complete verified512 outputs, with one common MVDR weight set per pixel."""
from pathlib import Path
import csv
import json
import numpy as np
from udp512 import beam_values,decode,RESULT


def aggregate(db,plan,output,mode,render=True,error=None):
    from m512_scan import audit_rows,unpack_packets
    output=Path(output);rows=audit_rows(db,plan)
    shape=(plan.nf,plan.nl,512)
    real=np.full(shape,np.nan);imag=np.full(shape,np.nan);complete=np.zeros(shape[:2],bool)
    with (output/'beam_records.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['frequency_mhz','relative_lag_samples','period_index','frame_id','I_raw_int48','Q_raw_int48','gain','I_rescaled','Q_rescaled','source'])
        for row in rows:
            fp,lp,_=plan.coordinate(row['ordinal']);gain=float(plan.gains[fp,lp]);values=[];fid=None
            for data in unpack_packets(row['received']):
                packet=decode(data)
                if packet.kind==RESULT:values.extend(beam_values(packet));fid=packet.frame_id
            if len(values)!=512:raise ValueError('incomplete512 output')
            for period,(r,i) in enumerate(values):
                real[fp,lp,period]=r/gain;imag[fp,lp,period]=i/gain
                writer.writerow([plan.meta['frequency_mhz'][fp],plan.meta['relative_lag_samples'][lp],period,f'0x{fid:08X}',r,i,gain,r/gain,i/gain,mode])
            complete[fp,lp]=True
    mean_power=np.mean(real*real+imag*imag,axis=-1)
    sr=real.sum(axis=-1);si=imag.sum(axis=-1);coherent=sr*sr+si*si
    distance=(np.asarray(plan.meta['relative_lag_samples'])+1)*7.68
    np.savez_compressed(output/'scan_results.npz',frequency_mhz=plan.meta['frequency_mhz'],relative_lag_samples=plan.meta['relative_lag_samples'],
        reference_script_range_km=distance,beam_re_rescaled=real,beam_im_rescaled=imag,
        coherent_sum_re_rescaled=sr,coherent_sum_im_rescaled=si,power=mean_power,coherent_power=coherent,
        pixel_complete=complete,source=mode,records_per_weight_set=512,joint_512_record_weights=True,effective_channels=14,active_channel_mask=0x7f7f)
    with (output/'ionogram_power.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['frequency_mhz','relative_lag_samples','reference_script_range_km','complete','mean_power','coherent512_power','coherent_sum_I','coherent_sum_Q','source'])
        for fp,freq in enumerate(plan.meta['frequency_mhz']):
            for lp,lag in enumerate(plan.meta['relative_lag_samples']):
                values=[mean_power[fp,lp],coherent[fp,lp],sr[fp,lp],si[fp,lp]] if complete[fp,lp] else ['']*4
                writer.writerow([freq,lag,distance[lp],bool(complete[fp,lp]),*values,mode])
    summary=dict(status=('COMPLETE_' if len(rows)==plan.meta['frames'] else 'PARTIAL_')+mode.upper(),source=mode,hardware_measurements=mode=='hardware',
        protocol='BFM1/2',plan_sha256=plan.hash,plan_directory=str(plan.path),planned_frames=plan.meta['frames'],verified_frames=len(rows),
        effective_channels=14,active_channel_mask=0x7f7f,excluded_channels=[7,15],complete_pixels=int(complete.sum()),planned_pixels=plan.nf*plan.nl,records_per_frame=512,joint_512_record_weights=True,
        attempts=db.execute('SELECT count(*) FROM attempts').fetchone()[0],run_error=error,
        integration='one shared MVDR weight set per512 periods; sum512 complex outputs before power',
        range_conversion='HF reference (lag+1)*7.68km; no independent calibration',
        physical_parameters_verified=False,prepared_numerical_quality=plan.meta['fixed_model_quality'],
        actual_reference_code_sha256=plan.meta['reference_files_sha256']['m255a.mat'],no_reference_fill=True,no_automatic_retry=True)
    if render:
        summary['plot']=plot(output,plan,coherent,mode,len(rows),True)
        summary['noncoherent_plot']=plot(output,plan,mean_power,mode,len(rows),False)
    (output/'scan_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    (output/'说明.txt').write_text(
        f"来源：{mode}；hardware为实际板卡，emulator仅是协议自测。已核对{len(rows)}/{plan.meta['frames']}帧。\n"
        "每个位置14有效通道（16路接口）×512周期联合求一组MVDR权值，再回放同一512周期。不是16个独立32周期权值组。\n"
        "ionogram.png：全部512复数回传先按gain还原，再相干求和取功率；ionogram_noncoherent.png为功率平均对照。\n"
        "beam_records.csv包含逐周期signed48 I/Q与还原分量；scan.sqlite3保留全部配置、32个输入包及49个ACK/结果回包。\n"
        "仅完整核对的16个RESULT包可提交一个位置。缺失点留空/NaN/灰色，不用软件参考补填。\n"
        f"输入实际m255a码表4相位相关；本计划{plan.nf}频点×{plan.nl}延迟，少量点计划仅作验收抽样，不是全部1020延迟。\n"
        "范围采用HF脚本(lag+1)*7.68km，未绝对校准。主图中位功率/ln2估计背景不是物理SNR。\n"
        "通道同步与幅相校准按用户说明；实际阵元坐标与物理指向仍需核对；增加512周期不能保证改善自消零。\n",encoding='utf-8-sig')
    return summary


def plot(output,plan,power,mode,verified,coherent):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    from plot_m_ionogram import edges
    font_path='C:/Windows/Fonts/msyh.ttc'
    font_manager.fontManager.addfont(font_path)
    font=font_manager.FontProperties(fname=font_path).get_name()
    valid=np.isfinite(power)
    if coherent:
        background=np.full((plan.nf,1),np.nan)
        for fi in range(plan.nf):
            if valid[fi].any():background[fi,0]=max(float(np.median(power[fi,valid[fi]])/np.log(2)),1e-30)
        data=10*np.log10(np.maximum(power,1e-30)/background)
        lo,hi=0.,40.
        bar='背景相对功率（dB，中位数/ln2估计；非校准SNR）'
        method='512周期复数相干求和；全帧同组权值'
        reference=dict(background_by_frequency=background[:,0].tolist(),method='median_power/ln2')
    else:
        peak=float(power[valid].max()) if valid.any() else 1.
        peak=max(peak,1e-30);data=10*np.log10(np.maximum(power,1e-30)/peak)
        lo=float(data[valid].min()) if valid.any() else -1.
        hi=0.
        if lo>=hi:lo=hi-1
        bar='相对功率（dB，已完成像素共同峰值=0）'
        method='512周期输出功率平均（对照图）'
        reference=dict(reference_power=peak,method='shared_peak')
    fi=np.asarray(plan.meta['source_frequency_index'],int)
    freq=np.asarray(plan.meta['frequency_mhz'])
    fstep=(freq[-1]-freq[0])/(fi[-1]-fi[0]) if len(fi)>1 else .5
    lags=np.asarray(plan.meta['relative_lag_samples'],int)
    step=min(4,int(np.gcd.reduce(np.diff(lags)))) if len(lags)>1 else 4
    dense_f=np.arange(fi[0],fi[-1]+1)*fstep+(freq[0]-fi[0]*fstep)
    dense_l=np.arange(lags[0],lags[-1]+1,step)
    dense_d=(dense_l+1)*7.68
    display=np.full((len(dense_f),len(dense_l)),np.nan)
    display[np.ix_(fi-fi[0],(lags-lags[0])//step)]=data
    def boundaries(a,spacing):return edges(a) if len(a)>1 else np.array([a[0]-spacing/2,a[0]+spacing/2])
    cmap=plt.get_cmap('viridis').copy();cmap.set_bad('#bbbbbb')
    source='实板回包' if mode=='hardware' else '协议自测（非实板、非回波测量）'
    filename='ionogram.png' if coherent else 'ionogram_noncoherent.png'
    with plt.rc_context({'font.family':font,'font.size':12,'axes.unicode_minus':False}):
        fig=plt.figure(figsize=(9,7.6));ax=fig.add_axes([.12,.24,.66,.58]);cax=fig.add_axes([.81,.24,.025,.58])
        mesh=ax.pcolormesh(boundaries(dense_f,fstep),boundaries(dense_d,step*7.68),
            np.ma.masked_invalid(display.T),cmap=cmap,vmin=lo,vmax=hi,shading='flat',rasterized=True)
        ax.set(xlabel='名义频率（MHz）',ylabel='参考脚本群距离（km；未校准）')
        ax.set_ylim(bottom=0)
        fig.suptitle(f'M实际参考码 · MVDR · {source}\n{method} · 已验证{verified}/{plan.meta["frames"]}帧',fontsize=15,y=.96)
        fig.colorbar(mesh,cax=cax,label=bar,extend='both' if coherent else 'neither')
        fig.text(.5,.045,'实际m255a码表；4相位独立相关；每帧14有效通道（16路接口）×512周期，联合求一组权值。\n'
            '只显示已核对回包；缺失为灰色，无插值、平滑或参考值补填。\n'
            '距离沿用(lag+1)×7.68km；阵列映射/指向及距离零点未校准。\n'
            '完整512周期联合协方差与权值；不是32周期分块拼接。',ha='center',va='bottom',fontsize=9)
        fig.savefig(Path(output)/filename,dpi=180,facecolor='white');plt.close(fig)
    return dict(filename=filename,db_limits=[lo,hi],reference=reference,
        below_display_limit=int((data[valid]<lo).sum()),above_display_limit=int((data[valid]>hi).sum()),
        raw_values_retained=True,interpolation=False,smoothing=False,missing_colour='#bbbbbb')
