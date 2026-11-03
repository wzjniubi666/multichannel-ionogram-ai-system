"""Provisional raw-M COS processing with explicit code/layout assumptions.

No network traffic, RTL edits, or implicit overwrite. Values are trial outputs,
not calibrated physical range or verified equipment code alignment.
"""
from __future__ import annotations
import argparse
from contextlib import nullcontext
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import platform
import re
import time

import numpy as np
from mvdr_reference import l16_positions, steering_vector


@dataclass(frozen=True)
class MProfile:
    order: int = 8
    samples_per_chip: int = 4
    sample_period_us: float = 25.6
    records: int = 512
    initial_state: str = "11111111"
    chip_phase: int = 0
    dtype: str = ">i2"

    @property
    def chips(self):
        return (1 << self.order) - 1

    @property
    def points(self):
        return self.chips * self.samples_per_chip

    def validate(self):
        if self.order != 8 or self.samples_per_chip < 1 or self.records < 1:
            raise ValueError("this trial implements order 8 with positive sampling/record counts")
        if self.dtype not in (">i2", "<i2") or not np.isfinite(self.sample_period_us) or self.sample_period_us <= 0:
            raise ValueError("invalid sample profile")
        if len(self.initial_state) != 8 or set(self.initial_state) - {"0", "1"} or "1" not in self.initial_state:
            raise ValueError("initial state must be eight bits and nonzero")


def validate_chips(chips):
    chips = np.asarray(chips, dtype=float)
    if chips.shape != (255,) or not np.all(np.isin(chips, (-1, 1))):
        raise ValueError("expected 255 bipolar chips")
    ac = np.fft.ifft(abs(np.fft.fft(chips)) ** 2).real
    if not np.allclose(ac[0], 255, atol=1e-9) or not np.allclose(ac[1:], -1, atol=1e-9):
        raise ValueError("chips do not have maximal-sequence cyclic autocorrelation")
    return chips


def make_chips(profile: MProfile):
    profile.validate()
    # Thesis table 2.4: x^8+x^4+x^3+x^2+1.
    # Define bit orientation explicitly: b[n+8]=b[n+4]^b[n+3]^b[n+2]^b[n].
    bits = [int(x) for x in profile.initial_state]
    for n in range(8, 263):
        bits.append(bits[n-4] ^ bits[n-5] ^ bits[n-6] ^ bits[n-8])
    if bits[255:263] != bits[:8]:
        raise ValueError("code period failed")
    chips = validate_chips(2 * np.asarray(bits[:255], dtype=float) - 1)
    return np.roll(chips, profile.chip_phase)


def circular_compress(x, sampled_code):
    """r[l]=sum_n x[n]*conj(code[n-l])/sum(abs(code)^2)."""
    x, code = np.asarray(x), np.asarray(sampled_code)
    if code.ndim != 1 or x.shape[-1] != code.size or not code.size:
        raise ValueError("circular compression requires complete equally sized periods")
    energy = float(np.vdot(code, code).real)
    if not energy > 0:
        raise ValueError("empty-energy matched code")
    spectrum = np.fft.fft(x, axis=-1)
    spectrum *= np.fft.fft(code).conj() / energy
    return np.fft.ifft(spectrum, axis=-1)


class RawMCapture:
    def __init__(self, folder: Path, profile: MProfile):
        profile.validate()
        folder = Path(folder)
        files, prefixes = {}, set()
        for path in folder.glob("*.cos"):
            m = re.fullmatch(r"(.+),ch_(\d+)\.cos", path.name, re.I)
            if not m or not m[1].startswith("M,"):
                raise ValueError("select one complete raw M capture directory")
            ch = int(m[2])
            if ch in files:
                raise ValueError("duplicate channel/capture")
            files[ch] = path
            prefixes.add(m[1])
        if set(files) != set(range(16)) or len(prefixes) != 1:
            raise ValueError("select one capture with channels 0..15, never mix different times")
        self.prefix = prefixes.pop()
        fields = self.prefix.split(",")
        start, step, stop = map(float, fields[2].split("_"))
        if not np.isfinite([start, step, stop]).all() or step <= 0 or stop < start:
            raise ValueError("invalid frequency labels")
        nf = round((stop-start)/step)+1
        if not np.isclose(start+(nf-1)*step, stop, rtol=0, atol=1e-9):
            raise ValueError("nonintegral nominal frequency grid")
        self.frequency_mhz = start + step * np.arange(nf)
        self.files = [files[ch] for ch in range(16)]
        self.profile = profile
        expected = nf * profile.records * profile.points * 4
        self.before = [(p.stat().st_size, p.stat().st_mtime_ns) for p in self.files]
        if any(size != expected for size, _ in self.before):
            raise ValueError(f"candidate layout needs exactly {expected} bytes per channel")
        self.maps = [np.memmap(p, mode="r", dtype=profile.dtype,
                     shape=(nf, profile.records, profile.points, 2)) for p in self.files]

    def read(self, fi):
        if not 0 <= fi < len(self.frequency_mhz):
            raise IndexError("frequency index out of bounds")
        out = np.empty((16, self.profile.records, self.profile.points), dtype=np.complex128)
        for ch, m in enumerate(self.maps):
            out[ch].real = m[fi, ..., 0]
            out[ch].imag = m[fi, ..., 1]
        return out

    def unchanged(self):
        return self.before == [(p.stat().st_size, p.stat().st_mtime_ns) for p in self.files]


def form_compressed(x, a, loading=0.05, block_points=64):
    """Loaded MVDR per compressed lag; one set of weights over the record axis."""
    nc, records, points = x.shape
    if not loading > 0 or len(a) != nc or records < 1:
        raise ValueError("invalid MVDR configuration")
    names = ("single_noncoherent", "array_noncoherent", "cbf_noncoherent", "mvdr_noncoherent",
             "cbf_coherent_mean", "mvdr_coherent_mean")
    products = {name: np.empty(points) for name in names}
    weights = np.empty((points, nc), complex)
    sums_cbf, sums_mvdr = np.empty(points, complex), np.empty(points, complex)
    constraint = np.empty(points)
    condition = np.empty(points)
    order_error = 0.0
    for first in range(0, points, block_points):
        last = min(points, first+block_points)
        block = x[:, :, first:last]
        z = np.ascontiguousarray(block.transpose(2, 0, 1))
        r = z @ z.conj().transpose(0, 2, 1) / records
        r = (r + r.conj().transpose(0, 2, 1)) / 2
        delta = loading * np.maximum(np.trace(r, axis1=1, axis2=2).real/nc, 1e-12)
        loaded = r + delta[:, None, None] * np.eye(nc)
        v = np.linalg.solve(loaded, np.broadcast_to(a, (last-first, nc))[..., None])[..., 0]
        denom = np.einsum("c,gc->g", a.conj(), v)
        if np.any(abs(denom) < 1e-30):
            raise ArithmeticError("MVDR denominator vanished")
        w = v / denom[:, None]
        weights[first:last] = w
        cbf = np.einsum("c,ckg->kg", (a / np.vdot(a, a).real).conj(), block)
        beam = np.einsum("gc,ckg->kg", w.conj(), block)
        sb, sm = cbf.sum(axis=0), beam.sum(axis=0)
        sums_cbf[first:last], sums_mvdr[first:last] = sb, sm
        products["single_noncoherent"][first:last] = np.mean(abs(block[0])**2, axis=0)
        products["array_noncoherent"][first:last] = np.mean(abs(block)**2, axis=(0, 1))
        products["cbf_noncoherent"][first:last] = np.mean(abs(cbf)**2, axis=0)
        products["mvdr_noncoherent"][first:last] = np.mean(abs(beam)**2, axis=0)
        products["cbf_coherent_mean"][first:last] = abs(sb/records)**2
        products["mvdr_coherent_mean"][first:last] = abs(sm/records)**2
        constraint[first:last] = abs(w.conj() @ a - 1)
        condition[first:last] = np.linalg.cond(loaded)
        alternate = np.einsum("gc,cg->g", w.conj(), block.sum(axis=1))
        order_error = max(order_error, float(np.linalg.norm(alternate-sm)/max(np.linalg.norm(sm), 1e-20)))
    if not np.isfinite(weights).all() or constraint.max() > 1e-8:
        raise ArithmeticError("nonfinite weights or failed steering constraint")
    return products, weights, sums_cbf, sums_mvdr, constraint, condition, order_error


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda: f.read(4*1024*1024), b""):
            h.update(b)
    return h.hexdigest().upper()


def render(out, frequency, arrays):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import Normalize
    panels = [("raw_ch0_noncoherent", "Raw channel 0", "Fast-time sample index"),
              ("single_noncoherent", "M-code matched filter: channel 0", "Relative correlation lag (samples)"),
              ("cbf_noncoherent", "Matched filter + conventional beam", "Relative correlation lag (samples)"),
              ("mvdr_noncoherent", "Matched filter + loaded MVDR", "Relative correlation lag (samples)")]
    db = [10*np.log10(np.maximum(arrays[name], 1e-12)) for name, _, _ in panels]
    lo, hi = min(float(d.min()) for d in db), max(float(d.max()) for d in db)
    step = frequency[1]-frequency[0] if len(frequency)>1 else .5
    edges = np.r_[frequency-step/2, frequency[-1]+step/2]
    lags = np.arange(db[0].shape[1]+1)-.5
    with plt.rc_context({"font.family":"DejaVu Sans", "font.size":11, "pdf.fonttype":42}):
        fig, axes = plt.subplots(2, 2, figsize=(14, 9), layout="constrained")
        for ax, values, (_, title, ylabel) in zip(axes.flat, db, panels):
            mesh = ax.pcolormesh(edges, lags, values.T, cmap="cividis", norm=Normalize(lo, hi), shading="flat")
            ax.set(title=title, xlabel="Nominal frequency (MHz)", ylabel=ylabel)
        fig.suptitle("Provisional raw-M trial | 20260714_100000 | code phase and layout unverified", fontsize=14)
        fig.colorbar(mesh, ax=axes, label="10 log10(mean power / 1 stored-count squared)")
        fig.text(.5, .012, "Matched filter normalized by code energy (1020). Shared full-range color scale; no smoothing.\n"
                 "Beam panels use training records; lower MVDR power is not a measured target/SNR gain.",
                 ha="center", va="bottom", fontsize=9)
        # Fixed canvas; keep the caption inside the page.
        fig.set_constrained_layout_pads(h_pad=.10, w_pad=.1)
        fig.get_layout_engine().set(rect=(0,.07,1,.93))
        fig.savefig(out/"overview.png", dpi=180, facecolor="white")
        fig.savefig(out/"overview.pdf", facecolor="white")
        plt.close(fig)
    return dict(common_db_limits=[lo,hi], power_floor=1e-12, interpolation="none",
                normalization="matched filter divided by code energy; noncoherent mean over stored records")


def run(args):
    profile = MProfile(records=args.records, initial_state=args.initial_state, chip_phase=args.chip_phase)
    capture = RawMCapture(args.folder, profile)
    chips = make_chips(profile)
    sampled_code = np.repeat(chips, profile.samples_per_chip)
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    nf, points = len(capture.frequency_mhz), profile.points
    assumptions = dict(layout="frequency,record,fast-time,IQ; candidate, not receiver-protocol verified",
        sample_period_us="25.6 assumed equal to elementary time; not measured ADC interval",
        code_polynomial="x^8+x^4+x^3+x^2+1; thesis table 2.4",
        code_initial_state="all ones by default, not captured from transmitter",
        code_phase="relative phase only; no calibrated absolute delay",
        bit_to_chip="0 -> -1, 1 -> +1",
        iq_order="I then Q, assumed", frequency_order="ascending, assumed from filename",
        array="16-element L extension, 8 per arm, 10m spacing, origin empty; mapping unverified",
        pointing="113deg azimuth, 35deg elevation, local convention; uncalibrated",
        record_semantics="512 stored blocks, not independently confirmed raw pulse identities",
        integration="coherent sums retained; no inter-capture or verified Doppler compensation")
    manifest = dict(profile=asdict(profile), chips=profile.chips, points=points,
        chip_time_us=profile.sample_period_us*profile.samples_per_chip,
        period_us=profile.points*profile.sample_period_us, capture_prefix=capture.prefix,
        assumptions=assumptions, raw_m_stage_confirmed_by_user=True,
        hardware_validation=False, rtl_changed=False, code_sha256=sha256(Path(__file__)),
        numpy_version=np.__version__, python=platform.python_version(),
        source=[dict(path=str(p.resolve()),bytes=before[0],mtime_ns=before[1])
                for p,before in zip(capture.files,capture.before)])
    (out/"manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    np.save(out/"chips.npy",chips)
    np.save(out/"sampled_code.npy",sampled_code)
    arrays = {name:np.empty((nf,points)) for name in (
        "raw_ch0_noncoherent", "single_noncoherent", "array_noncoherent", "cbf_noncoherent",
        "mvdr_noncoherent", "cbf_coherent_mean", "mvdr_coherent_mean")}
    weights=np.empty((nf,points,16),complex)
    cbf_sum=np.empty((nf,points),complex);mvdr_sum=np.empty_like(cbf_sum)
    constraint=np.empty((nf,points));condition=np.empty_like(constraint)
    max_order_error=0.0
    selected=int(np.argmin(abs(capture.frequency_mhz-10.0)))
    t0=time.perf_counter()
    try:
        from threadpoolctl import threadpool_limits
        context=threadpool_limits(limits=2)
    except ImportError:
        context=nullcontext()
    with context:
        for fi,f in enumerate(capture.frequency_mhz):
            raw=capture.read(fi)
            arrays["raw_ch0_noncoherent"][fi]=np.mean(abs(raw[0])**2,axis=0)
            x=circular_compress(raw,sampled_code)
            if fi==selected:
                np.savez_compressed(out/"selected_10mhz_first32.npz",raw=raw[:,:32],compressed=x[:,:32],
                    sampled_code=sampled_code,frequency_mhz=f,
                    note="Provisional complete code periods; no calibrated range-gate identity")
            del raw
            a=steering_vector(l16_positions(10),113,35,299792458/(f*1e6))
            p,w,sb,sm,ce,cn,oe=form_compressed(x,a)
            for name,data in p.items():arrays[name][fi]=data
            weights[fi]=w;cbf_sum[fi]=sb;mvdr_sum[fi]=sm;constraint[fi]=ce;condition[fi]=cn
            max_order_error=max(max_order_error,oe)
            del x
            print(f"Processed {fi+1}/{nf}: {f:g} MHz; max constraint error={ce.max():.3g}",flush=True)
    np.savez_compressed(out/"products.npz",frequency_mhz=capture.frequency_mhz,
        relative_lag_samples=np.arange(points),mvdr_weights=weights,
        cbf_coherent_sum=cbf_sum,mvdr_coherent_sum=mvdr_sum,
        constraint_error=constraint,loaded_condition_number=condition,**arrays)
    if not capture.unchanged():raise RuntimeError("source files changed during processing")
    for row in manifest["source"]:
        row["sha256"]=sha256(row["path"])
    if not capture.unchanged():raise RuntimeError("source files changed during hashing")
    plot=render(out,capture.frequency_mhz,arrays)
    manifest.update(elapsed_processing_seconds=time.perf_counter()-t0,plot=plot,
        processed_frequencies=nf,max_constraint_error=float(constraint.max()),
        max_fixed_weight_sum_order_relative_error=max_order_error,
        loaded_condition_number_range=[float(condition.min()),float(condition.max())],
        status="PROVISIONAL_TRIAL_COMPLETE; physical code/layout/alignment not verified")
    (out/"manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    print("PASS M_PROVISIONAL_PIPELINE: raw read + circular compression + 16ch CBF/MVDR; assumptions retained")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder",type=Path)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--records",type=int,default=512)
    parser.add_argument("--initial-state",default="11111111")
    parser.add_argument("--chip-phase",type=int,default=0)
    run(parser.parse_args())
