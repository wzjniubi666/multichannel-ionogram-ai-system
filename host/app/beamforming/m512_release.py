"""Gate512 host execution on exact verified implementation, image, protocol and model."""
from pathlib import Path
import json
from m_sequence_pipeline import sha256
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'validation/m_hf512_20261026'


def check_release(plan):
    path=BASE/'release.json';seal=json.loads(path.read_text(encoding='utf-8'))
    if seal['status']!='READY_JOINT512_FOR_USER_HARDWARE':raise ValueError('joint512 release not ready')
    for name,wanted in seal['execution_source_sha256'].items():
        if sha256(ROOT/name)!=wanted:raise ValueError('joint512 execution source changed: '+name)
    for name,wanted in seal['evidence_sha256'].items():
        if sha256(BASE/name)!=wanted:raise ValueError('joint512 release evidence changed: '+name)
    manifest=json.loads((BASE/'programming_v1/manifest.json').read_text(encoding='utf-8'))
    if manifest['top']!='kt325t_network512_board_top' or manifest['protocol']!='BFM1/2' or manifest['records']!=512:
        raise ValueError('wrong joint512 image identity')
    if sha256(manifest['bitstream'])!=manifest['bitstream_sha256']:raise ValueError('512 image modified')
    directory=Path(manifest['implementation_directory'])
    implementation=json.loads((directory/'implementation_summary.json').read_text(encoding='utf-8'))
    if implementation['status']!='PASS_JOINT512_IMPLEMENTATION':raise ValueError('512 physical implementation not accepted')
    if sha256(manifest['source_checkpoint'])!=manifest['source_checkpoint_sha256']:raise ValueError('accepted512 checkpoint changed')
    for row in json.loads((directory/'source_hashes.json').read_text(encoding='utf-8-sig')):
        if sha256(row['Path'])!=row['Hash']:raise ValueError('512 implementation snapshot changed')
    normal=json.loads((BASE/'network_sim_v1/verification.json').read_text(encoding='utf-8'))
    if not normal['passed'] or normal['records_per_frame']!=512 or normal['ack_result_packets']!=441:
        raise ValueError('joint512 sequential verification missing')
    if normal['plan_source_code_sha256']!=plan.meta['source_code_sha256']:raise ValueError('512 preparation model differs from tested model')
    tested=json.loads((BASE/'network_plan_v1/plan.json').read_text(encoding='utf-8'))
    if tested['reference_files_sha256']!=plan.meta['reference_files_sha256']:raise ValueError('512 reference code mismatch')
    for relative,wanted in normal['source_sha256'].items():
        if sha256(ROOT/relative)!=wanted:raise ValueError('tested512 RTL changed')
    return dict(protocol='BFM1/2',records_per_weight_set=512,bitstream=manifest['bitstream'],
        bitstream_sha256=manifest['bitstream_sha256'],release_sha256=sha256(path),
        joint512_hardware_tested_at_release=False,geometry_calibrated=False)
