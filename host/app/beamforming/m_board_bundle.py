"""Load a 32-record M bundle only after exact core and wire-level simulation."""
from dataclasses import replace
from pathlib import Path
import hashlib
import json
import struct
from udp_replay import configuration,iq_packets,read_hex,decode,RESULT,beam_values


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def verify_released_image(root):
    release=Path(root)/'validation/board_20261023/network_rxfix/programming_rxfix_v2/manifest.json'
    metadata=json.loads(release.read_text(encoding='utf-8'))
    source_manifest=Path(metadata['source_checkpoint']).parent/'source_hashes.json'
    if digest(source_manifest)!=metadata['source_manifest_sha256']:
        raise ValueError('released source manifest hash mismatch')
    rows=json.loads(source_manifest.read_text(encoding='utf-8-sig'))
    count=0
    for row in rows:
        snapshot=Path(row['Path'])
        if snapshot.parent.name!='sources' or snapshot.suffix!='.v':continue
        current=Path(root)/'rtl'/snapshot.name
        if not current.exists():current=Path(root)/'vendor/pz_udp_rgmii_reference'/snapshot.name
        if digest(snapshot)!=row['Hash'] or digest(current)!=row['Hash']:
            raise ValueError('production source differs from released image: '+snapshot.name)
        count+=1
    if count!=25 or digest(metadata['bitstream'])!=metadata['bitstream_sha256']:
        raise ValueError('released source count or bitstream hash mismatch')
    return dict(production_sources=count,source_manifest_sha256=metadata['source_manifest_sha256'],
                bitstream_sha256=metadata['bitstream_sha256'])


def prepare_m(frame_id,vectors):
    vectors=Path(vectors).resolve()
    meta=json.loads((vectors/'manifest.json').read_text(encoding='utf-8'))
    proof=json.loads((vectors/'hardware_ready.json').read_text(encoding='utf-8'))
    if meta['waveform']!='M' or (meta['channels'],meta['snapshots'])!=(16,32):
        raise ValueError('a 16-channel 32-record M bundle is required')
    if proof.get('status')!='PASS_M32_CORE_AND_RGMII_SIMULATION':
        raise ValueError('M bundle has not passed core and RGMII validation')
    if digest(vectors/'manifest.json')!=proof['manifest_sha256']:
        raise ValueError('M manifest differs from validated bundle')
    for name,expected in proof['vector_sha256'].items():
        if digest(vectors/name)!=expected:
            raise ValueError(f'M vector changed after simulation: {name}')
    if proof['vector_sha256']!=meta['vector_sha256']:
        raise ValueError('vector manifest/proof mismatch')
    for row in proof['evidence']:
        if digest(row['path'])!=row['sha256']:
            raise ValueError('accepted M simulation evidence changed')
    verify_released_image(Path(__file__).resolve().parents[1])
    cfg=configuration(read_hex(vectors/'steering_re.hex',24),read_hex(vectors/'steering_im.hex',24),
        proof['config_id'],meta['frequency_index'],meta['gate_index'])
    iq=iq_packets(read_hex(vectors/'iq_i.hex',16),read_hex(vectors/'iq_q.hex',16),
        frame_id,cfg.config_id,cfg.frequency_index,cfg.gate_index)
    reference_path=Path(proof['reference_packet'])
    reference=decode(b''.join(struct.pack('!I',int(w,16)) for w in reference_path.read_text().split()))
    if reference.kind!=RESULT or len(beam_values(reference))!=32:
        raise ValueError('invalid accepted M response')
    wire=Path(proof['wire_directory'])
    for name,packet in [('config',cfg),('iq0',iq[0]),('iq1',iq[1])]:
        tested=decode((wire/(name+'.bin')).read_bytes()[50:-4])
        if replace(tested,frame_id=packet.frame_id)!=packet:
            raise ValueError('M payload does not match simulated wire input')
    if (reference.config_id,reference.frequency_index,reference.gate_index)!=(cfg.config_id,cfg.frequency_index,cfg.gate_index):
        raise ValueError('accepted M result metadata mismatch')
    return cfg,iq,replace(reference,frame_id=frame_id)
