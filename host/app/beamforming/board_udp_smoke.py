"""Export one board transaction; --host explicitly enables real UDP traffic."""
from __future__ import annotations

import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import socket
import struct
import uuid

from udp_replay import (RESULT, Packet, beam_values, configuration, decode,
                        exchange, iq_packets, read_hex)

ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "sim_vectors/reference_10mhz_gate80"
RTL_RESULT = ROOT / "validation/board_20261023/network_rxfix/regression/reference_network_result.hex"


def prepare(frame_id: int, vectors: Path | None = None):
    if vectors is not None:
        from m_board_bundle import prepare_m
        return prepare_m(frame_id, vectors)
    meta = json.loads((VECTORS / "manifest.json").read_text(encoding="utf-8-sig"))
    cfg = configuration(read_hex(VECTORS / "steering_re.hex", 24),
                        read_hex(VECTORS / "steering_im.hex", 24),
                        0x10203040, meta["frequency_index"], meta["gate_index"])
    iq = iq_packets(read_hex(VECTORS / "iq_i.hex", 16),
                    read_hex(VECTORS / "iq_q.hex", 16), frame_id, cfg.config_id,
                    cfg.frequency_index, cfg.gate_index)
    # The board is fixed-point: use its accepted bit-exact RTL reference, rather
    # than treating floating-point Python beam estimates as bit-exact results.
    reference = decode(b"".join(struct.pack("!I", int(w, 16)) for w in RTL_RESULT.read_text().split()))
    if reference.kind != RESULT or len(beam_values(reference)) != 32:
        raise ValueError("invalid accepted RTL reference")
    for name, current in (("config", cfg), ("iq0", iq[0]), ("iq1", iq[1])):
        wire = (RTL_RESULT.parent / "gmii" / f"{name}.bin").read_bytes()
        accepted = decode(wire[50:-4])  # 8 preamble + Ethernet14 + IPv4 20 + UDP8.
        if replace(accepted, frame_id=current.frame_id) != current:
            raise ValueError(f"current {name} differs from accepted board input fixture")
    if (reference.config_id, reference.frequency_index, reference.gate_index) != (
            cfg.config_id, cfg.frequency_index, cfg.gate_index):
        raise ValueError("accepted RTL reference/input metadata mismatch")
    expected = replace(reference, frame_id=frame_id)
    return cfg, iq, expected


def compare_result(actual: Packet, expected: Packet):
    if actual != expected:
        different = [i for i, (a, b) in enumerate(zip(beam_values(actual), beam_values(expected))) if a != b]
        raise ValueError(f"BOARD_RESULT_MISMATCH: differing records={different}; metadata also checked")


class RecordedSocket:
    def __init__(self, sock, output: Path):
        self.sock, self.output, self.stage = sock, output, "before_config"
        self.received = 0

    def send(self, data):
        packet = decode(data)
        self.stage = "waiting_config_ack" if packet.kind == 1 else "waiting_result"
        return self.sock.send(data)

    def recv(self, size):
        data = self.sock.recv(size)
        self.received += 1
        (self.output / f"received_{self.received}.bin").write_bytes(data)
        return data


def transact(sock, output: Path, cfg, iq, expected):
    recorded = RecordedSocket(sock, output)
    try:
        actual = exchange(recorded, cfg, iq)
        compare_result(actual, expected)
        (output / "result.bin").write_bytes(actual.encode())
        return dict(passed=True, frame_id=actual.frame_id, complex_records=32,
                    exact_payload_bytes=384, beam=beam_values(actual))
    except Exception as exc:
        (output / "failure.json").write_text(json.dumps(dict(
            stage=recorded.stage, received_datagrams=recorded.received,
            error_type=type(exc).__name__, error=str(exc)), indent=2), encoding="utf-8")
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--host", choices=["192.0.2.1"])
    parser.add_argument("--vectors", type=Path, help="validated M32 bundle; omitted preserves the accepted legacy C test")
    parser.add_argument("--frame-id", type=lambda x: int(x, 0), default=uuid.uuid4().int & 0xFFFFFFFF)
    args = parser.parse_args()
    cfg, iq, expected = prepare(args.frame_id, args.vectors)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for name, packet in (("config", cfg), ("iq0", iq[0]), ("iq1", iq[1]), ("expected_result", expected)):
        (output / f"{name}.bin").write_bytes(packet.encode())
    vectors = args.vectors.resolve() if args.vectors else VECTORS
    vector_meta = json.loads((vectors / "manifest.json").read_text(encoding="utf-8-sig"))
    reference_path = (Path(json.loads((vectors / "hardware_ready.json").read_text(encoding="utf-8"))["reference_packet"])
                      if args.vectors else RTL_RESULT)
    meta = dict(frame_id=args.frame_id, board_ip="192.0.2.1", pc_ip="192.0.2.2",
                udp_port=5000, source_vector_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in vectors.glob("*.hex")},
                accepted_rtl_result_sha256=hashlib.sha256(reference_path.read_bytes()).hexdigest(),
                source_vectors=str(vectors), waveform=vector_meta.get("waveform", "C"),
                frequency_mhz=vector_meta["frequency_mhz"], frequency_index=cfg.frequency_index,
                relative_lag_or_stored_gate=cfg.gate_index, record_start=vector_meta.get("record_start", 0),
                records=32, quantization=vector_meta.get("quantization"),
                mode="network" if args.host else "offline", no_automatic_retry=True)
    (output / "manifest.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    if not args.host:
        print(f"INPUT_IDENTITY: waveform={meta['waveform']} frequency={meta['frequency_mhz']}MHz "
              f"index={cfg.frequency_index} lag_or_gate={cfg.gate_index} records={meta['record_start']}..{meta['record_start']+31}")
        print("PASS BOARD_UDP_OFFLINE: requests prepared; 384 reference bytes match accepted RTL; no traffic")
        return
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(3.0)
        sock.bind(("192.0.2.2", 5000))
        sock.connect((args.host, 5000))
        result = transact(sock, output, cfg, iq, expected)
    (output / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("PASS BOARD_UDP_EXACT: CONFIG ACK and all 32 complex records match accepted RTL byte for byte")


if __name__ == "__main__":
    main()
