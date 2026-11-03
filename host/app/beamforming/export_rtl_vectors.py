"""Export reproducible integer RTL inputs and floating MVDR references."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from mvdr_reference import load_cos_gate, l16_positions, steering_vector


def hex_file(path, values, width):
    values = [int(v) for v in np.asarray(values).reshape(-1)]
    if any(v < -(1 << (width-1)) or v >= (1 << (width-1)) for v in values):
        raise ValueError(f"overflow in {path.name}")
    path.write_text("".join(f"{v & ((1 << width)-1):0{(width+3)//4}x}\n" for v in values), encoding="ascii")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "XCK325Tboshuhecheng/sim_vectors/reference_10mhz_gate80")
    p.add_argument("--frequency-mhz", type=float, default=10.0)
    p.add_argument("--gate", type=int, default=80)
    p.add_argument("--records", type=int, default=32)
    p.add_argument("--loading", type=float, default=0.05)
    args = p.parse_args()
    # Strict channel mapping; actual files may have a receiver prefix.
    files = []
    for ch in range(16):
        matches = list(args.folder.glob(f"*ch_{ch:02d}.cos"))
        if len(matches) != 1:
            raise ValueError(f"channel {ch}: expected exactly one file")
        files.append(matches[0])
    x = load_cos_gate(args.folder, args.frequency_mhz, args.gate, n_ch=16, records=args.records)
    ii, qq = x.real.astype(np.int64), x.imag.astype(np.int64)
    rr = ii @ ii.T + qq @ qq.T
    ri = qq @ ii.T - ii @ qq.T
    a = steering_vector(l16_positions(10), 113, 35, 299792458 / (args.frequency_mhz*1e6))
    scale = 1 << 23
    ar = np.clip(np.rint(a.real * scale), -scale, scale-1).astype(np.int64)
    ai = np.clip(np.rint(a.imag * scale), -scale, scale-1).astype(np.int64)
    aq = (ar + 1j*ai) / scale
    # Integer loading on the unaveraged covariance, nearest integer, ties up.
    trace = int(np.trace(rr))
    if args.loading < 0:
        raise ValueError("loading must be nonnegative")
    delta = int(np.floor(args.loading * trace / 16 + 0.5))
    loaded = rr + delta*np.eye(16, dtype=np.int64) + 1j*ri
    z = np.linalg.solve(loaded, aq)
    w = z / np.vdot(aq, z)
    wr, wi = np.rint(w.real*scale).astype(np.int64), np.rint(w.imag*scale).astype(np.int64)
    yr = (wr @ ii + wi @ qq) >> 23
    yi = (wr @ qq - wi @ ii) >> 23
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    for name, data, width in [
        ("iq_i", ii.T, 16), ("iq_q", qq.T, 16),
        ("cov_re", rr, 48), ("cov_im", ri, 48),
        ("loaded_re", loaded.real.astype(np.int64), 48),
        ("steering_re", ar, 24), ("steering_im", ai, 24),
        ("weight_re", wr, 24), ("weight_im", wi, 24),
        ("beam_re", yr, 48), ("beam_im", yi, 48)]:
        hex_file(out / (name+".hex"), data, width)
    np.savez(out / "reference.npz", iq=x, covariance_sum=rr+1j*ri,
             steering_ideal=a, steering_quantized=aq, loaded=loaded, weights=w,
             weights_quantized=(wr+1j*wi)/scale, beam_float=w.conj()@x)
    metadata = dict(channels=16, snapshots=args.records, frequency_mhz=args.frequency_mhz,
        frequency_index=round((args.frequency_mhz-2.0)/0.05), gate_index=args.gate,
        stored_records=args.records, azimuth_deg=113,
        elevation_deg=35, spacing_m=10, weight_frac=23, loading=args.loading,
        loading_integer=delta, covariance_scale="sum, not mean",
        iq_order="snapshot*16+channel", matrix_order="row*16+column",
        hex_encoding="signed two's complement, one word per line",
        steering_convention="exp(-j*2*pi*p.u/lambda), u=(cos(el)*sin(az),cos(el)*cos(az),sin(el)); local azimuth assumption",
        data_scope="one gate across stored records at selected frequency; frequency order and record semantics remain unverified",
        cos_shape="frequency 361 x stored record 32 x gate 320 x IQ 2 (tested compatible layout)",
        device_accumulations_configured=512, device_accumulation_stage="unknown",
        geometry_scope="8 elements per arm, origin empty; assumed mapping ch0..7 x, ch8..15 y",
        condition_number=float(np.linalg.cond(loaded)),
        constraint_error=float(abs(np.vdot(w, aq)-1)),
        sources=[dict(file=f.name, first_1024_bytes_sha256=hashlib.sha256(f.read_bytes()[:1024]).hexdigest()) for f in files])
    (out / "manifest.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Exported {out}: condition={metadata['condition_number']:.6g}, loading_integer={delta}, constraint_error={metadata['constraint_error']:.3g}")


if __name__ == "__main__":
    main()
