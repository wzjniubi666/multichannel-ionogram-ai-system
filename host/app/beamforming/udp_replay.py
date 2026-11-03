"""BFM1 v1 codec, offline COS packet export, and stop-and-wait UDP playback.

Default operation only writes local artifacts. Network traffic requires --host.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import socket
import struct

MAGIC = 0x42464D31
CONFIG, IQ, ACK, RESULT, ERROR = 1, 2, 0x81, 0x82, 0xFF
ERRORS = {1: "FORMAT", 2: "BAD_PACKET", 3: "CONFIG", 4: "SEQUENCE",
          5: "BUSY", 6: "TIMEOUT", 7: "SOLVER", 8: "CORE_TIMEOUT"}
HEADER = struct.Struct("!IBBHIIHHHHHHHH")


@dataclass(frozen=True)
class Packet:
    kind: int
    frame_id: int
    config_id: int
    frequency_index: int
    gate_index: int
    index: int = 0
    count: int = 1
    status: int = 0
    payload: bytes = b""

    def encode(self) -> bytes:
        data = HEADER.pack(MAGIC, 1, self.kind, self.status, self.frame_id,
                           self.config_id, self.frequency_index, self.gate_index,
                           self.index, self.count, 32, 16, len(self.payload), 0) + self.payload
        decode(data)  # One strict validation path for outbound and inbound packets.
        return data


def decode(data: bytes) -> Packet:
    if len(data) < HEADER.size or len(data) > 1056 or len(data) % 4:
        raise ValueError("invalid datagram size")
    magic, version, kind, status, fid, cid, freq, gate, idx, count, records, channels, size, reserved = HEADER.unpack_from(data)
    if (magic, version, records, channels, reserved) != (MAGIC, 1, 32, 16, 0):
        raise ValueError("invalid protocol header")
    if size != len(data) - HEADER.size:
        raise ValueError("payload size mismatch")
    if kind not in (CONFIG, IQ, ACK, RESULT, ERROR):
        raise ValueError("unknown packet type")
    if kind == ERROR:
        if status not in ERRORS or size or count != 1:
            raise ValueError("invalid error packet")
    else:
        if status:
            raise ValueError("unexpected status")
        expected = {CONFIG: 96, IQ: 1024, ACK: 0, RESULT: 384}[kind]
        if size != expected or count != (2 if kind == IQ else 1) or idx >= count:
            raise ValueError("invalid payload or packet index")
        if kind in (CONFIG, ACK) and fid != 0:
            raise ValueError("configuration frame_id must be zero")
    return Packet(kind, fid, cid, freq, gate, idx, count, status, data[HEADER.size:])


def signed_bytes(value: int, bits: int) -> bytes:
    return int(value).to_bytes(bits // 8, "big", signed=True)


def configuration(re: list[int], im: list[int], cid: int, freq: int, gate: int) -> Packet:
    if len(re) != 16 or len(im) != 16:
        raise ValueError("16 steering coefficients required")
    payload = b"".join(signed_bytes(r, 24) + signed_bytes(i, 24) for r, i in zip(re, im))
    return Packet(CONFIG, 0, cid, freq, gate, payload=payload)


def iq_packets(ii: list[int], qq: list[int], fid: int, cid: int, freq: int, gate: int) -> list[Packet]:
    if len(ii) != 512 or len(qq) != 512:
        raise ValueError("32 records x 16 channels required in record-major order")
    payload = b"".join(signed_bytes(i, 16) + signed_bytes(q, 16) for i, q in zip(ii, qq))
    return [Packet(IQ, fid, cid, freq, gate, p, 2, payload=payload[p*1024:(p+1)*1024]) for p in range(2)]


def beam_values(packet: Packet) -> list[tuple[int, int]]:
    if packet.kind != RESULT or len(packet.payload) != 384:
        raise ValueError("not a result")
    return [(int.from_bytes(packet.payload[p:p+6], "big", signed=True),
             int.from_bytes(packet.payload[p+6:p+12], "big", signed=True))
            for p in range(0, 384, 12)]


def exchange(sock, config: Packet, packets: list[Packet]) -> Packet:
    """Socket must be connected to a single endpoint with a finite timeout.

    No automatic retries: an ambiguous timeout requires a new frame ID / explicit recovery.
    """
    def receive(kind, fid):
        response = decode(sock.recv(2048))
        if (response.frame_id, response.config_id, response.frequency_index, response.gate_index) != (
                fid, config.config_id, config.frequency_index, config.gate_index):
            raise ValueError("response metadata mismatch (stale or foreign transaction)")
        if response.kind == ERROR:
            raise RuntimeError(f"FPGA {ERRORS[response.status]} frame={response.frame_id}")
        if response.kind != kind:
            raise ValueError("unexpected response type")
        return response
    if len(packets) != 2 or any(p.kind != IQ for p in packets):
        raise ValueError("two IQ packets required")
    if packets[0].index != 0 or packets[1].index != 1 or packets[0].frame_id != packets[1].frame_id:
        raise ValueError("IQ sequence mismatch")
    for p in packets:
        if (p.config_id, p.frequency_index, p.gate_index) != (config.config_id, config.frequency_index, config.gate_index):
            raise ValueError("IQ/config metadata mismatch")
    sock.send(config.encode())
    receive(ACK, 0)
    for packet in packets:
        sock.send(packet.encode())
    return receive(RESULT, packets[0].frame_id)


def read_hex(path: Path, bits: int) -> list[int]:
    values = [int(v, 16) for v in path.read_text(encoding="ascii").split()]
    if any(v >= 1 << bits for v in values):
        raise ValueError(f"word overflow: {path}")
    return [v - (1 << bits) if v & (1 << (bits-1)) else v for v in values]


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=Path, default=root / "sim_vectors/reference_10mhz_gate80")
    parser.add_argument("--cos-folder", type=Path, help="load IQ directly from COS using vector manifest frequency/gate")
    parser.add_argument("--output", type=Path, default=root / "validation/network_20261021/packets")
    parser.add_argument("--frame-id", type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument("--config-id", type=lambda x: int(x, 0), default=0x10203040)
    parser.add_argument("--host", help="explicit FPGA IP; omitted means offline export only")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--local-port", type=int, default=5000,
                        help="bind PC UDP port; must match FPGA PEER_PORT for the static endpoint")
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()
    meta = json.loads((args.vectors / "manifest.json").read_text(encoding="utf-8-sig"))
    if meta["channels"] != 16 or meta["snapshots"] != 32:
        raise ValueError("unsupported vector dimensions")
    ii, qq = read_hex(args.vectors / "iq_i.hex", 16), read_hex(args.vectors / "iq_q.hex", 16)
    if args.cos_folder:
        from mvdr_reference import load_cos_gate
        values = load_cos_gate(args.cos_folder, meta["frequency_mhz"], meta["gate_index"], n_ch=16, records=32)
        ii = values.real.T.astype("int64").reshape(-1).tolist()
        qq = values.imag.T.astype("int64").reshape(-1).tolist()
    sr, si = read_hex(args.vectors / "steering_re.hex", 24), read_hex(args.vectors / "steering_im.hex", 24)
    config = configuration(sr, si, args.config_id, meta["frequency_index"], meta["gate_index"])
    packets = iq_packets(ii, qq, args.frame_id, args.config_id, config.frequency_index, config.gate_index)
    args.output.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for name, p in zip(("config", "iq0", "iq1"), (config, *packets)):
        data = p.encode()
        (args.output / f"{name}.bin").write_bytes(data)
        (args.output / f"{name}.hex").write_text("".join(f"{w:08x}\n" for (w,) in struct.iter_unpack("!I", data)), encoding="ascii")
        hashes[name] = hashlib.sha256(data).hexdigest()
    manifest = dict(protocol="BFM1/1", frame_id=args.frame_id, config_id=args.config_id,
                    frequency_index=config.frequency_index, gate_index=config.gate_index,
                    source_vectors=str(args.vectors.resolve()), source_cos=str(args.cos_folder) if args.cos_folder else None,
                    assumptions=meta, packet_sha256=hashes)
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Exported CONFIG + 2 IQ packets: {args.output}")
    if args.host:
        if args.timeout <= 0 or not 1 <= args.port <= 65535 or not 1 <= args.local_port <= 65535:
            raise ValueError("positive timeout and valid remote/local ports required")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(args.timeout)
            sock.bind(("0.0.0.0", args.local_port))
            sock.connect((args.host, args.port))
            result = exchange(sock, config, packets)
        (args.output / "result.bin").write_bytes(result.encode())
        (args.output / "result.json").write_text(json.dumps(dict(frame_id=result.frame_id,
            beam=beam_values(result)), indent=2), encoding="utf-8")
        print(f"Received 32 beam records for frame {result.frame_id}")


if __name__ == "__main__":
    main()
