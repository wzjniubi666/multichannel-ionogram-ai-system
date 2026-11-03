#!/usr/bin/env python3
"""Floating-point reference for the loaded SMI/MVDR beamformer.

The input format follows the current engineering assumption: one big-endian
signed-int16 file per channel, with interleaved I,Q words.  The implementation
is deliberately independent of the RTL so it can serve as an algorithm and
fixed-point comparison reference.

Examples:
    python mvdr_reference.py --demo
    python mvdr_reference.py ..\20260602_183600 --snapshots 4096 --spacing 0.5
    python mvdr_reference.py ..\paper_data --array l6 --frequency-mhz 10
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re

import numpy as np


def channel_number(path: Path) -> int:
    try:
        return int(path.stem.lower().rsplit("ch_", 1)[1])
    except (IndexError, ValueError):
        return 999


def _legacy_capture_files(folder: Path, n_ch: int) -> dict[int, Path]:
    """Select one complete capture; this reader supports the old C layout only.

    Raw M data needs an explicit fast/slow-time layout and code correlation.
    Refuse it before treating an arbitrary stored point as a range gate.
    """
    folder = Path(folder)
    if not isinstance(n_ch, int) or n_ch < 1:
        raise ValueError("channel count must be a positive integer")
    paths = list(folder.glob("*.cos"))
    if not paths:
        raise ValueError(f"no .cos files directly in {folder}; select one capture subdirectory")
    files = {}
    prefixes = set()
    for path in paths:
        match = re.search(r",ch_(\d+)\.cos$", path.name, re.IGNORECASE)
        if not match:
            raise ValueError(f"unrecognized capture filename: {path.name}")
        ch = int(match.group(1))
        if ch in files:
            raise ValueError(f"duplicate channel {ch}: choose one capture, do not mix acquisition times")
        files[ch] = path
        prefixes.add(path.name[:match.start()])
    if set(files) != set(range(n_ch)):
        raise ValueError(f"expected channels 0..{n_ch-1}, found {sorted(files)}")
    if len(prefixes) != 1:
        raise ValueError("channel capture identifiers differ")
    waveform = next(iter(prefixes)).split(",", 1)[0].upper()
    if waveform == "M":
        raise ValueError("raw M capture is not supported by the legacy C reader: confirm record/fast-time layout "
                         "and apply the actual M-code matched filter before selecting compressed range gates")
    if waveform != "C":
        raise ValueError(f"unsupported capture waveform {waveform!r}; an explicit format profile is required")
    return files


def load_iq(folder: Path, n_ch: int = 16, snapshots: int | None = None) -> np.ndarray:
    """Return legacy C IQ pairs; flattened pairs are not physical slow-time snapshots."""
    files = _legacy_capture_files(folder, n_ch)
    channels = []
    for path in (files[ch] for ch in range(n_ch)):
        raw = path.read_bytes()
        if len(raw) % 4:
            raise ValueError(f"{path.name} does not contain complete I/Q pairs")
        words = np.frombuffer(raw, dtype=">i2")
        z = words[0::2].astype(np.float64) + 1j * words[1::2].astype(np.float64)
        channels.append(z)
    count = min(z.size for z in channels)
    if snapshots is not None:
        if snapshots <= 0:
            raise ValueError("snapshots must be positive")
        count = min(count, snapshots)
    return np.asarray([z[:count] for z in channels], dtype=np.complex128)


def load_cos_gate(folder: Path, frequency_mhz: float, gate: int,
                  n_ch: int = 16, records: int = 32) -> np.ndarray:
    """Read one legacy C frequency/stored-point slice, shape (channel, record)."""
    files = _legacy_capture_files(folder, n_ch)
    names = {files[ch].name.rsplit(",ch_", 1)[0] for ch in files}
    if len(names) != 1:
        raise ValueError("channel capture identifiers differ")
    start, step, stop = map(float, next(iter(names)).split(",")[2].split("_"))
    frequency_count = round((stop - start) / step) + 1
    index = round((frequency_mhz - start) / step)
    if not 0 <= index < frequency_count or not np.isclose(start + index * step, frequency_mhz, atol=1e-8):
        raise ValueError("frequency is outside the capture grid")
    gates = 320  # Tested organization of this capture, not a confirmed receiver protocol.
    if not 0 <= gate < gates or not 1 <= records <= 32:
        raise ValueError("gate must be 0..319 and records must be 1..32")
    result = np.empty((n_ch, records), dtype=np.complex128)
    for ch in range(n_ch):
        path = files[ch]
        expected_bytes = frequency_count * 32 * gates * 4
        if path.stat().st_size != expected_bytes:
            raise ValueError(f"{path.name}: expected {expected_bytes} bytes")
        words = np.memmap(path, mode="r", dtype=">i2", shape=(frequency_count, 32, gates, 2))
        pairs = words[index, :records, gate]
        result[ch] = pairs[:, 0].astype(np.float64) + 1j * pairs[:, 1].astype(np.float64)
    return result


def steering_vector(
    positions: np.ndarray,
    azimuth_deg: float,
    elevation_deg: float = 0.0,
    wavelength: float = 1.0,
) -> np.ndarray:
    """Create a phase-only steering vector from Cartesian positions.

    Positions and wavelength use the same units.  The direction convention is
    u=(cos(elevation)*sin(azimuth), cos(elevation)*cos(azimuth), sin(elevation)).
    """
    p = np.asarray(positions, dtype=np.float64)
    if p.ndim != 2 or p.shape[1] != 3:
        raise ValueError("positions must have shape (N, 3)")
    if wavelength <= 0:
        raise ValueError("wavelength must be positive")
    az = np.deg2rad(azimuth_deg)
    el = np.deg2rad(elevation_deg)
    direction = np.array([np.cos(el) * np.sin(az), np.cos(el) * np.cos(az), np.sin(el)])
    return np.exp(-1j * 2.0 * np.pi * (p @ direction) / wavelength)


def ula_positions(n_ch: int, spacing_wavelengths: float = 0.5) -> np.ndarray:
    if n_ch <= 0 or spacing_wavelengths <= 0:
        raise ValueError("channel count and spacing must be positive")
    x = (np.arange(n_ch) - (n_ch - 1) / 2.0) * spacing_wavelengths
    return np.column_stack((x, np.zeros(n_ch), np.zeros(n_ch)))


def l6_positions(spacing_m: float = 10.0) -> np.ndarray:
    """Six-element L array from the paper: origin empty, three per axis."""
    if spacing_m <= 0:
        raise ValueError("spacing_m must be positive")
    # x is east-west and y is south-north; the reference element is omitted.
    return np.asarray([
        [spacing_m, 0.0, 0.0], [2.0 * spacing_m, 0.0, 0.0],
        [3.0 * spacing_m, 0.0, 0.0], [0.0, spacing_m, 0.0],
        [0.0, 2.0 * spacing_m, 0.0], [0.0, 3.0 * spacing_m, 0.0],
    ])


def l16_positions(spacing_m: float = 10.0) -> np.ndarray:
    """Sixteen-element extension of the paper's L array.

    The paper uses three elements on each arm with the origin empty.  For
    this 16-channel design, each arm is extended to eight elements while
    retaining the paper's 10 m spacing and east-west/north-south geometry.
    """
    if spacing_m <= 0:
        raise ValueError("spacing_m must be positive")
    arm = np.arange(1, 9, dtype=np.float64) * spacing_m
    return np.vstack([
        np.column_stack((arm, np.zeros(8), np.zeros(8))),
        np.column_stack((np.zeros(8), arm, np.zeros(8))),
    ])


def mvdr_weights(
    X: np.ndarray,
    steering: np.ndarray,
    loading: float = 0.01,
) -> tuple[np.ndarray, np.ndarray, float]:
    """Return (weights, loaded covariance, loading diagonal value)."""
    X = np.asarray(X, dtype=np.complex128)
    a = np.asarray(steering, dtype=np.complex128).reshape(-1)
    if X.ndim != 2 or X.shape[0] != a.size or X.shape[1] < 1:
        raise ValueError("X must have shape (N, K), matching steering")
    if loading < 0:
        raise ValueError("loading must be non-negative")
    R = (X @ X.conj().T) / X.shape[1]
    diagonal = float(loading * np.trace(R).real / X.shape[0])
    R_loaded = R + diagonal * np.eye(X.shape[0], dtype=np.complex128)
    z = np.linalg.solve(R_loaded, a)
    denominator = np.vdot(a, z)
    if abs(denominator) < 1e-15:
        raise np.linalg.LinAlgError("MVDR normalization denominator is too small")
    return z / denominator, R_loaded, diagonal


def beam_output(weights: np.ndarray, X: np.ndarray) -> np.ndarray:
    """Compute y=w^H X, matching complex_beamformer.v."""
    return np.asarray(weights).conj() @ np.asarray(X)


def demo() -> None:
    rng = np.random.default_rng(7)
    positions = ula_positions(16)
    target = steering_vector(positions, 0.0)
    interferer = steering_vector(positions, 35.0)
    X = target[:, None] * (2.0 + 0.1j * rng.standard_normal(256))
    X += 3.0 * interferer[:, None] * (rng.standard_normal(256) + 1j * rng.standard_normal(256))
    X += 0.05 * (rng.standard_normal(X.shape) + 1j * rng.standard_normal(X.shape))
    w, _, diagonal = mvdr_weights(X, target, loading=0.01)
    response_target = np.vdot(w, target)
    response_interferer = np.vdot(w, interferer)
    assert np.allclose(response_target, 1.0, atol=1e-10)
    print(f"demo: diagonal_loading={diagonal:.6g}")
    print(f"demo: target_response={response_target.real:+.6f}{response_target.imag:+.6f}j")
    print(f"demo: interferer_response_db={20*np.log10(abs(response_interferer)+1e-15):+.2f}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", type=Path)
    parser.add_argument("--snapshots", type=int, default=32,
                        help="stored records used at the selected frequency/gate (1..32)")
    parser.add_argument("--gate", type=int, default=80,
                        help="stored gate index, 0..319; default is a diagnostic example")
    parser.add_argument("--azimuth", type=float, default=113.0)
    parser.add_argument("--elevation", type=float, default=35.0)
    parser.add_argument("--spacing", type=float, default=0.5, help="ULA spacing in wavelengths")
    parser.add_argument("--array", choices=("ula", "l6", "l16"), default="l16",
                        help="l16 is the 16-channel paper-parameter L extension; ula/l6 are compatibility modes")
    parser.add_argument("--spacing-m", type=float, default=10.0,
                        help="L6 adjacent element spacing in metres (paper: 10)")
    parser.add_argument("--frequency-mhz", type=float, default=10.0,
                        help="carrier frequency for L-array steering (paper experiment: 5-15 MHz)")
    parser.add_argument("--loading", type=float, default=0.05)
    parser.add_argument("--demo", action="store_true")
    args = parser.parse_args()
    if args.demo:
        demo()
        return
    if args.folder is None:
        parser.error("folder is required unless --demo is used")
    n_ch = 6 if args.array == "l6" else 16
    X = load_cos_gate(args.folder, args.frequency_mhz, args.gate,
                      n_ch=n_ch, records=args.snapshots)
    if args.array in ("l6", "l16"):
        if args.frequency_mhz is None or args.frequency_mhz <= 0:
            parser.error("--frequency-mhz must be positive with an L-array mode")
        wavelength_m = 299_792_458.0 / (args.frequency_mhz * 1e6)
        positions = l6_positions(args.spacing_m) if args.array == "l6" else l16_positions(args.spacing_m)
    else:
        wavelength_m = 1.0
        positions = ula_positions(X.shape[0], args.spacing)
    a = steering_vector(positions, args.azimuth, args.elevation, wavelength_m)
    w, R, diagonal = mvdr_weights(X, a, args.loading)
    y = beam_output(w, X)
    print(f"channels={X.shape[0]} records={X.shape[1]} gate={args.gate} array={args.array}")
    if args.array in ("l6", "l16"):
        print(f"frequency_mhz={args.frequency_mhz:g} spacing_m={args.spacing_m:g} wavelength_m={wavelength_m:.9g}")
    print(f"loading_diagonal={diagonal:.9g} condition_number={np.linalg.cond(R):.6g}")
    print(f"constraint={np.vdot(w, a):.9g} output_rms={np.sqrt(np.mean(abs(y)**2)):.9g}")
    for index, value in enumerate(w):
        print(f"w[{index:02d}]={value.real:+.9g}{value.imag:+.9g}j")


if __name__ == "__main__":
    main()
