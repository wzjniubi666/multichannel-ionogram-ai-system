"""Integer MVDR reference: explicit RTL widths, truncation and Q16.16 elimination.

This is a numerical model, not a cycle-accurate simulator. Timing/handshakes
are checked separately by the HDL testbench.
"""
from __future__ import annotations


def signed(value, bits):
    value = int(value) & ((1 << bits)-1)
    return value-(1 << bits) if value & (1 << (bits-1)) else value


def trunc_div(numerator, denominator):
    if denominator == 0:
        raise ZeroDivisionError("MVDR zero divisor")
    result = abs(int(numerator)) // abs(int(denominator))
    return -result if (numerator < 0) != (denominator < 0) else result


def multiply(a, b, conjugate=False):
    ar, ai = a
    br, bi = b
    real = ar*br + ai*bi if conjugate else ar*br-ai*bi
    imag = ai*br-ar*bi if conjugate else ai*br+ar*bi
    return signed(real,129), signed(imag,129)


def solve_fixed(cov_re, cov_im, steer_re, steer_im, active_mask=None):
    n = len(steer_re)
    if len(steer_im) != n or len(cov_re) != n or len(cov_im) != n:
        raise ValueError("inconsistent dimensions")
    mask=(1<<n)-1 if active_mask is None else int(active_mask)
    if mask<=0 or mask>=(1<<n):
        raise ValueError('active mask must select at least one existing channel')
    active=[bool(mask&(1<<i)) for i in range(n)]
    count=sum(active)
    # Copy and mask here as well: the solver contract is independent of whether
    # upstream IQ was correctly masked, including cross-covariance entries.
    cov_re=[[int(cov_re[i][j]) if active[i] and active[j] else 0 for j in range(n)] for i in range(n)]
    cov_im=[[int(cov_im[i][j]) if active[i] and active[j] else 0 for j in range(n)] for i in range(n)]
    steer_re=[int(steer_re[i]) if active[i] else 0 for i in range(n)]
    steer_im=[int(steer_im[i]) if active[i] else 0 for i in range(n)]
    trace = signed(sum(int(cov_re[i][i]) for i in range(n)),64)
    mean = signed(trunc_div(trace,count),64) or 1
    delta = signed(trunc_div(signed(mean*5,64),100),64)
    matrix = [[(signed(trunc_div((int(cov_re[i][j])+((delta if active[i] else mean) if i==j else 0))<<16,mean),64),
                signed(trunc_div(int(cov_im[i][j])<<16,mean),64))
               for j in range(n)] for i in range(n)]
    vector = [(int(r)>>7,int(i)>>7) for r,i in zip(steer_re,steer_im)]
    for pivot in range(n):
        p = matrix[pivot][pivot]
        norm = multiply(p,p,True)[0]
        if norm == 0:
            raise ZeroDivisionError("MVDR zero pivot")
        def normalize(z):
            r,i = multiply(z,p,True)
            return (signed(trunc_div(signed(r<<16,129),norm),64),
                    signed(trunc_div(signed(i<<16,129),norm),64))
        for col in range(pivot,n):
            matrix[pivot][col] = normalize(matrix[pivot][col])
        vector[pivot] = normalize(vector[pivot])
        for row in range(n):
            if row == pivot:
                continue
            factor = matrix[row][pivot]
            def eliminate(target, source):
                r,i = multiply(factor,source)
                return (signed(target[0]-(signed(r,128)>>16),64),
                        signed(target[1]-(signed(i,128)>>16),64))
            for col in range(pivot+1,n):
                matrix[row][col] = eliminate(matrix[row][col],matrix[pivot][col])
            vector[row] = eliminate(vector[row],vector[pivot])
    denominator = 0
    for r,i,v in zip(steer_re,steer_im,vector):
        product = multiply((int(r),int(i)),v,True)[0]
        denominator = signed(denominator+(signed(product,128)>>7),64)
    weights = [(signed(trunc_div(signed(r<<39,64),denominator),24),
                signed(trunc_div(signed(i<<39,64),denominator),24)) for r,i in vector]
    weights=[weight if active[i] else (0,0) for i,weight in enumerate(weights)]
    return weights, dict(trace=trace,mean_power=mean,loading_integer=delta,denominator=denominator,
                         active_mask=mask,active_channels=count)


def beam_fixed(ii,qq,weights):
    """Inputs are channel x record, output record-major signed 48-bit values."""
    k = len(ii[0])
    result=[]
    for record in range(k):
        real=imag=0
        for ch,(wr,wi) in enumerate(weights):
            real += int(ii[ch][record])*wr + int(qq[ch][record])*wi
            imag += int(qq[ch][record])*wr - int(ii[ch][record])*wi
        result.append((signed(real,48)>>23,signed(imag,48)>>23))
    return result
