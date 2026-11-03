from pathlib import Path
import tempfile
import unittest
import numpy as np
from m_sequence_pipeline import (MProfile, RawMCapture, circular_compress,
                                 form_compressed, make_chips, validate_chips)
from mvdr_reference import mvdr_weights


class MPipelineTests(unittest.TestCase):
    def test_code_period_and_corruption(self):
        chips=make_chips(MProfile())
        ac=np.fft.ifft(abs(np.fft.fft(chips))**2).real
        self.assertEqual(len(chips),255)
        np.testing.assert_allclose(ac,np.r_[255,np.full(254,-1)],atol=1e-9)
        bad=chips.copy();bad[9]*=-1
        with self.assertRaisesRegex(ValueError,'autocorrelation'):validate_chips(bad)
        with self.assertRaises(ValueError):make_chips(MProfile(initial_state='00000000'))

    def test_fft_filter_matches_direct_definition(self):
        x=np.array([1+2j,3-1j,-2j,4+3j])
        # Circularly asymmetric code distinguishes correlation from convolution.
        code=np.array([1,1,-1,-1])
        expected=np.array([sum(x[n]*code[(n-l)%4].conjugate() for n in range(4))/4 for l in range(4)])
        np.testing.assert_allclose(circular_compress(x,code),expected,atol=1e-12)
        with self.assertRaises(ValueError):circular_compress(x,np.ones(5))

    def test_known_m_echo_peak_and_normalization(self):
        code=np.repeat(make_chips(MProfile()),4)
        x=(2+3j)*np.roll(code,37)
        y=circular_compress(x,code)
        self.assertEqual(int(np.argmax(abs(y))),37)
        np.testing.assert_allclose(y[37],2+3j,atol=1e-12)
        np.testing.assert_allclose(y[(37+4*np.arange(1,255))%1020],-(2+3j)/255,atol=1e-12)

    def test_batched_mvdr_matches_scalar_reference(self):
        rng=np.random.default_rng(17)
        x=rng.normal(size=(16,32,3))+1j*rng.normal(size=(16,32,3))
        a=np.exp(1j*np.linspace(0,2,16))
        products,w,cbf_sum,mvdr_sum,ce,cond,oe=form_compressed(x,a,block_points=2)
        for g in range(3):
            reference,_,_=mvdr_weights(x[:,:,g],a,loading=.05)
            np.testing.assert_allclose(w[g],reference,atol=1e-12)
            y=reference.conj()@x[:,:,g]
            np.testing.assert_allclose(products['mvdr_noncoherent'][g],np.mean(abs(y)**2),atol=1e-12)
            np.testing.assert_allclose(mvdr_sum[g],y.sum(),atol=1e-12)
        self.assertLess(float(ce.max()),1e-12)
        self.assertLess(oe,1e-12)

    def test_explicit_raw_layout_and_channel_mapping(self):
        profile=MProfile(records=2)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            pairs=np.arange(2*1020*2,dtype=np.int16).reshape(1,2,1020,2)
            for ch in range(16):
                name=f'M,512,7.000_0.500_7.000,8_4_4,20260714_100000,30N_113E,ch_{ch:02d}.cos'
                (root/name).write_bytes((pairs+ch).astype('>i2').tobytes())
            cap=RawMCapture(root,profile)
            x=cap.read(0)
            self.assertEqual(x.shape,(16,2,1020))
            self.assertEqual(x[5,1,10],complex(2065,2066))
            with self.assertRaisesRegex(ValueError,'candidate layout'):
                RawMCapture(root,MProfile(records=3))
            del cap


if __name__=='__main__':unittest.main()
