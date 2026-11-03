"""HFceshi actual-code, per-period, phase-wise correlation. No accumulation across periods."""
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from m_sequence_pipeline import sha256

METHOD = 'HF_M255_PHASE4_PER_PERIOD_V1'


def load_reference(path):
    path = Path(path)
    code = np.asarray(loadmat(path)['code']).ravel().astype(float)
    if code.shape != (255,) or not np.isin(code, [-1, 1]).all():
        raise ValueError('reference requires 255 actual bipolar chips')
    ac = np.fft.ifft(abs(np.fft.fft(code))**2).real
    if not np.allclose(ac[0], 255, atol=1e-9) or not np.allclose(ac[1:], -1, atol=1e-9):
        raise ValueError('reference is not a maximal-length 255-chip sequence')
    return code


def compress_periods(raw, code):
    raw = np.asarray(raw)
    if raw.ndim != 3 or raw.shape[0] != 16 or raw.shape[1:] != (512, 1020):
        raise ValueError('expected complex [16 channels,512 periods,1020 samples]')
    if np.asarray(code).shape != (255,) or not np.isfinite(raw).all():
        raise ValueError('invalid code or IQ')
    x = raw.reshape(16, 512, 255, 4)
    y = np.fft.ifft(np.fft.fft(x, axis=2)*np.fft.fft(code).conj()[None,None,:,None], axis=2)
    # int16 IQ and bipolar integer chips have exact integer correlation sums.
    # Remove FFT roundoff before gain scaling, so half-integer quantization
    # consistently follows ties-to-even instead of the FFT error's sign.
    rounded = np.rint(y.real) + 1j*np.rint(y.imag)
    if float(abs(y-rounded).max()) > 1e-6:
        raise ArithmeticError('input is not integer IQ or correlation roundoff exceeds its bound')
    return rounded.reshape(16, 512, 1020)


def verify_frequency(raw, compressed, code):
    """Independent exact integer dot checks span channels, periods and all phases."""
    maximum = 0.
    for channel, period, lag in ((0,0,0),(1,31,81),(7,32,254),(15,511,1019),(0,511,82)):
        chip_lag, phase = divmod(lag, 4)
        values = raw[channel, period, phase::4]
        shifted = np.roll(code, chip_lag).astype(np.int64)
        direct = np.dot(values.real.astype(np.int64), shifted) + 1j*np.dot(values.imag.astype(np.int64), shifted)
        error = float(abs(compressed[channel,period,lag]-direct))
        maximum = max(maximum,error)
        np.testing.assert_allclose(compressed[channel,period,lag],direct,rtol=1e-12,atol=1e-7)
    # The full 512-period sum must reproduce the reference-script formula for ch0.
    summed = raw[0].reshape(512,255,4).sum(axis=0)
    expected = np.fft.ifft(np.fft.fft(summed,axis=0)*np.fft.fft(code).conj()[:,None],axis=0).reshape(1020)
    np.testing.assert_allclose(compressed[0].sum(axis=0),expected,rtol=1e-10,atol=1e-6)
    return dict(direct_dot_max_abs_error=maximum, code_sha256=sha256_bytes(code))


def sha256_bytes(code):
    import hashlib
    return hashlib.sha256(np.asarray(code,dtype=np.int8).tobytes()).hexdigest().upper()
