"""Require exact actual-code M32 RTL evidence and a sealed tested host implementation."""
from pathlib import Path
import json
from m_board_bundle import verify_released_image
from m_reference_batch_plan import ReferenceScanPlan
from m_sequence_pipeline import sha256

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'validation/m_hf32_20261026'


def check_reference_release(plan):
    seal_path=EVIDENCE/'release.json'
    seal=json.loads(seal_path.read_text(encoding='utf-8'))
    if seal['status']!='READY_FOR_USER_HARDWARE_HF_M32':raise ValueError('reference M32 release not ready')
    for name,wanted in seal['execution_source_sha256'].items():
        if sha256(ROOT/name)!=wanted:raise ValueError('tested execution source changed: '+name)
    for name,wanted in seal['evidence_sha256'].items():
        if sha256(EVIDENCE/name)!=wanted:raise ValueError('reference release evidence changed: '+name)
    tested=ReferenceScanPlan(EVIDENCE/'network_plan_v2')
    normal=json.loads((EVIDENCE/'network_sim_v2/verification.json').read_text(encoding='utf-8'))
    mutation=json.loads((EVIDENCE/'network_mutation_v2/verification.json').read_text(encoding='utf-8'))
    for proof,mutated in ((normal,False),(mutation,True)):
        if not proof['passed'] or proof['mutation']!=mutated or proof['plan_sha256']!=tested.hash:
            raise ValueError('actual-code RTL/mutation proof mismatch')
        if proof['frames']!=9 or proof['ack_result_packets']!=18 or not proof['no_reset_between_frames']:
            raise ValueError('insufficient sequential coverage')
        if proof['plan_source_code_sha256']!=plan.meta['source_code_sha256']:
            raise ValueError('plan model not the sequentially tested model')
        for name,wanted in proof['source_sha256'].items():
            if sha256(ROOT/name)!=wanted:raise ValueError('tested RTL changed: '+name)
        directory=EVIDENCE/('network_mutation_v2' if mutated else 'network_sim_v2')
        for name,wanted in proof['evidence_sha256'].items():
            if sha256(directory/name)!=wanted:raise ValueError('RTL test output changed: '+name)
    if tested.meta['reference_files_sha256']!=plan.meta['reference_files_sha256']:
        raise ValueError('plan uses a different actual code/reference')
    anchor=ROOT/'validation/board_20261023/host_smoke_20261026_132811_d23fa6/hardware_verification_summary.json'
    if sha256(anchor)!=seal['prior_hardware_anchor_sha256']:
        raise ValueError('prior hardware transport/arithmetic evidence changed')
    return dict(image=verify_released_image(ROOT),release_sha256=sha256(seal_path),
        actual_code_sequential_frames_verified=9,expected_output_mutation_rejected=True,
        prior_hardware_anchor='legacy input; transport/arithmetic only, not corrected-input hardware acceptance',
        corrected_input_hardware_executed=False)
