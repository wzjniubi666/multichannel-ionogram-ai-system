"""Export an independently verified hardware M32 beam result without new traffic."""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import math
import shutil
import numpy as np
from udp_replay import decode,beam_values,signed_bytes


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def export(session,output):
    session=session.resolve();output=output.resolve()
    if output.exists():raise FileExistsError('use a new result subdirectory: '+str(output))
    proof_path=session/'hardware_verification_summary.json'
    proof=json.loads(proof_path.read_text(encoding='utf-8'))
    if proof['status']!='PASS_M32_SINGLE_FRAME_HARDWARE':raise ValueError('verified hardware M32 session required')
    metadata_path=session/'udp/manifest.json'
    raw_path=session/'udp/received_2.bin'
    evidence={key.replace('\\','/'):value for key,value in proof['evidence_sha256'].items()}
    for relative in ('udp/received_1.bin','udp/received_2.bin','udp/result.bin','udp/manifest.json'):
        if digest(session/relative)!=evidence[relative]:
            raise ValueError('session evidence changed: '+relative)
    metadata=json.loads(metadata_path.read_text(encoding='utf-8'))
    wire=raw_path.read_bytes()
    packet=decode(wire)
    beam=beam_values(packet)
    if (packet.frame_id!=proof['frame_id'] or len(beam)!=32
            or [list(x) for x in beam]!=proof['independently_decoded_beam']):
        raise ValueError('result/proof identity mismatch')
    if wire!=(session/'udp/result.bin').read_bytes():raise ValueError('raw/saved result differ')
    gain=float(metadata['quantization']['gain'])
    if not math.isfinite(gain) or gain<=0:raise ValueError('invalid input gain')
    output.mkdir(parents=True,exist_ok=False)
    shutil.copy2(raw_path,output/'fpga_result_udp.bin')
    shutil.copy2(session/'udp/received_1.bin',output/'config_ack_udp.bin')
    shutil.copy2(proof_path,output/'hardware_verification_summary.json')
    shutil.copy2(metadata_path,output/'session_manifest.json')
    (output/'beam_payload_iq48be.bin').write_bytes(packet.payload)
    csv_path=output/'beamformed.csv'
    with csv_path.open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f)
        writer.writerow(['record_index','I_raw_int48','Q_raw_int48','I_rescaled','Q_rescaled',
                         'amplitude_rescaled','power_rescaled'])
        for offset,(re,im) in enumerate(beam):
            r,i=re/gain,im/gain
            writer.writerow([metadata['record_start']+offset,re,im,r,i,math.hypot(r,i),r*r+i*i])
    integer=np.asarray(beam,dtype=np.int64)
    values=(integer[:,0].astype(float)+1j*integer[:,1])/gain
    np.savez_compressed(output/'beamformed.npz',record_index=metadata['record_start']+np.arange(32),
        I_raw_int48=integer[:,0],Q_raw_int48=integer[:,1],beam_complex_rescaled=values,
        input_quantization_gain=gain,frequency_mhz=metadata['frequency_mhz'],
        relative_correlation_lag_samples=packet.gate_index,frame_id=packet.frame_id)
    # Round-trip checks cover signed values, record order and binary payload layout.
    with csv_path.open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
    roundtrip=b''.join(signed_bytes(int(row['I_raw_int48']),48)+signed_bytes(int(row['Q_raw_int48']),48) for row in rows)
    if len(rows)!=32 or roundtrip!=packet.payload:raise RuntimeError('CSV payload round-trip failed')
    saved=np.load(output/'beamformed.npz')
    np.testing.assert_array_equal(saved['I_raw_int48'],integer[:,0])
    np.testing.assert_array_equal(saved['Q_raw_int48'],integer[:,1])
    np.testing.assert_array_equal(saved['beam_complex_rescaled'],values)
    text=f"""新M数据的FPGA实板MVDR波束合成结果

这是真实板卡回传数据，已与RTL参考逐字节核对，不是软件预测值。
来源：{session}
frame_id：0x{packet.frame_id:08X}
采集：{proof['capture_prefix']}
名义频率：{metadata['frequency_mhz']} MHz（索引{packet.frequency_index}）
相对相关延迟：{packet.gate_index}采样点；尚未校准绝对距离。
输入16通道，每帧32条；当前取记录{metadata['record_start']}..{metadata['record_start']+31}。

处理链路：PC做M码相关/脉冲压缩及量化 → FPGA计算协方差和MVDR权值 → 用同一组权值对同帧16通道加权求和 → 返回32个复数输出。
每个输出对应一个输入记录，y[k]=sum_ch(conj(w[ch])*x[ch,k])，是16通道合成后的一个波束输出。
这32行沿记录维排列，属于同一频点、同一相对延迟；不是32个频点、32个距离门或32个波束。

文件说明：
beamformed.csv：可直接用Excel或文本编辑器查看。I_raw_int48/Q_raw_int48为板卡回传的signed48实部/虚部整数。
I_rescaled/Q_rescaled：将回传整数除以输入量化增益{gain:g}，还原到本次压缩IQ的幅度尺度；不是伏特或瓦特校准值。
amplitude_rescaled和power_rescaled分别为复数模和模平方，不是SNR。
beamformed.npz：同一组整数及复数数组，供Python后续处理。
fpga_result_udp.bin：416字节完整UDP应用数据（32字节BFM1头+384字节结果负载），不含以太网/IP/UDP头。
beam_payload_iq48be.bin：384字节纯结果负载，每条依次为6字节大端有符号实部、6字节大端有符号虚部，共32条。
config_ack_udp.bin：配置ACK的原始UDP应用数据。
session_manifest.json和hardware_verification_summary.json：输入身份、量化与硬件验收证据。
export_manifest.json：导出来源/文件哈希及CSV、NPZ回读检查。

当前仅一个频点、一个相对延迟的一帧结果；不是完整512记录联合求权或整幅电离图。采集布局/实际码字/阵列映射仍沿用试算假设。
本次只是导出已收到的数据，没有重新向板卡发包或改动网络。
"""
    (output/'说明.txt').write_text(text,encoding='utf-8-sig')
    report=dict(status='EXPORTED_VERIFIED_HARDWARE_BEAM',source_session=str(session),
        source_hardware_verification_sha256=digest(proof_path),frame_id=f'0x{packet.frame_id:08X}',
        channels_in=16,complex_records_out=32,frequency_mhz=metadata['frequency_mhz'],
        relative_correlation_lag_samples=packet.gate_index,record_start=metadata['record_start'],
        raw_component_bits=48,payload_bytes=384,input_quantization_gain=gain,
        scale_rule='rescaled=(raw_real+j*raw_im)/input_quantization_gain; uncalibrated signal units',
        hardware_result=True,software_prediction=False,no_new_network_traffic=True,
        csv_binary_payload_roundtrip_exact=True,npz_roundtrip_exact=True,
        exporter_sha256=digest(Path(__file__)),
        files_sha256={p.name:digest(p) for p in output.iterdir() if p.is_file()})
    (output/'export_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'PASS RESULT_EXPORT: 32 measured complex beam outputs; CSV/binary/NPZ exact; {output}')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--session',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();export(a.session,a.output)
