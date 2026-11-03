"""Bind bulk execution to the tested model, production RTL and M32 hardware anchor."""
from pathlib import Path
import json
from m_sequence_pipeline import sha256
from m_board_bundle import verify_released_image

ROOT=Path(__file__).resolve().parents[1]


def check_batch_release(plan):
    evidence=ROOT/'validation/m_batch_20261026'
    files=[evidence/'network_sim_v1/verification.json',evidence/'network_mutation_v1/verification.json']
    normal,mutation=[json.loads(p.read_text(encoding='utf-8')) for p in files]
    if not normal['passed'] or normal['mutation'] or not mutation['passed'] or not mutation['mutation']:
        raise ValueError('sequential RTL verification/mutation missing')
    if normal['frames']!=9 or normal['ack_result_packets']!=18 or not normal['no_reset_between_frames']:
        raise ValueError('unexpected sequential RTL coverage')
    if normal['plan_source_code_sha256']!=plan.meta['source_code_sha256']:
        raise ValueError('prepared model differs from sequentially tested model')
    for proof in (normal,mutation):
        for path,expected in proof['source_sha256'].items():
            if sha256(ROOT/path)!=expected:raise ValueError('batch-tested RTL changed: '+path)
    for name,expected in normal['evidence_sha256'].items():
        if sha256(evidence/'network_sim_v1'/name)!=expected:raise ValueError('sequential RTL evidence changed')
    anchor=ROOT/'validation/board_20261023/host_smoke_20261026_132811_d23fa6/hardware_verification_summary.json'
    hardware=json.loads(anchor.read_text(encoding='utf-8'))
    if hardware['status']!='PASS_M32_SINGLE_FRAME_HARDWARE':raise ValueError('M32 hardware anchor missing')
    return dict(image=verify_released_image(ROOT),sequential_frames_verified=9,
        evidence_sha256={str(p):sha256(p) for p in files+[anchor]},
        full_batch_hardware_verified=False)
