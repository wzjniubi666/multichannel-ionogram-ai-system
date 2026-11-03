"""Explicit active14 image/plan gate; never substitute the legacy16 release."""
from pathlib import Path
import json
from m_sequence_pipeline import sha256
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'validation/m_hf512_14ch_20261028'


def check_release(plan):
    if plan.meta.get('active_channel_mask')!=0x7f7f or plan.meta.get('active_channels')!=14:
        raise ValueError('Wrong image profile: explicit active14 plan required')
    path=BASE/'release.json'
    seal=json.loads(path.read_text(encoding='utf-8'))
    if seal.get('status')!='READY_ACTIVE14_FOR_USER_HARDWARE':raise ValueError('Active14 image not accepted')
    if seal.get('active_mask')!=0x7f7f or seal.get('effective_channels')!=14:raise ValueError('Wrong active channel mask')
    for name,wanted in seal['execution_source_sha256'].items():
        if sha256(ROOT/name)!=wanted:raise ValueError('Active14 execution source changed: '+name)
    for name,wanted in seal['evidence_sha256'].items():
        if sha256(BASE/name)!=wanted:raise ValueError('Active14 evidence changed: '+name)
    image=json.loads((BASE/'programming_v1/manifest.json').read_text(encoding='utf-8'))
    if (image['top'],image['protocol'],image['records'],image['active_mask'])!=('kt325t_network512_board_top','BFM1/2',512,0x7f7f):
        raise ValueError('Wrong image identity')
    if sha256(image['bitstream'])!=image['bitstream_sha256']:raise ValueError('Active14 bitstream changed')
    if sha256(image['source_checkpoint'])!=image['source_checkpoint_sha256']:raise ValueError('Active14 checkpoint changed')
    proof=json.loads((BASE/'network14_actual_v3/verification.json').read_text(encoding='utf-8'))
    tested=json.loads((BASE/'actual11_plan14_v2/plan.json').read_text(encoding='utf-8'))
    if not proof['passed'] or proof['active_mask']!=0x7f7f:raise ValueError('Active14 functional proof absent')
    if plan.meta['source_code_sha256']!=tested['source_code_sha256']:raise ValueError('Active14 preparation model differs from tested model')
    if plan.meta['reference_files_sha256']!=tested['reference_files_sha256']:raise ValueError('Active14 reference code differs')
    return dict(protocol='BFM1/2',records_per_weight_set=512,effective_channels=14,active_channel_mask=0x7f7f,
        pointing_deg=[113,35],bitstream=image['bitstream'],bitstream_sha256=image['bitstream_sha256'],
        release_sha256=sha256(path),hardware_tested=False,physical_pointing_verified=False)
