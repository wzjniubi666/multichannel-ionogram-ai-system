from pathlib import Path
import struct
import unittest
import numpy as np
from export_m_rtl_vectors import quantize_iq
from mvdr_fixed_reference import signed,trunc_div,solve_fixed,beam_fixed
from udp_replay import read_hex,decode,beam_values

ROOT=Path(__file__).resolve().parents[1]


class MFixedTests(unittest.TestCase):
    def test_signed_and_negative_division_contract(self):
        self.assertEqual(signed(0x8000,16),-32768)
        self.assertEqual(signed(-32769,16),32767)
        self.assertEqual(trunc_div(-7,3),-2)
        self.assertEqual(trunc_div(7,-3),-2)
        self.assertEqual(trunc_div(-7,-3),2)
        with self.assertRaises(ZeroDivisionError):trunc_div(1,0)

    def test_quantization_rounding_extrema_and_saturation(self):
        x=np.array([[-40000+40000j,-1.5+2.5j,-.5+.5j,32767-32768j]])
        ii,qq,count=quantize_iq(x,1)
        np.testing.assert_array_equal(ii,[[-32768,-2,0,32767]])
        np.testing.assert_array_equal(qq,[[32767,2,0,-32768]])
        self.assertEqual(count,2)
        for gain in (0,-1,float('inf')):
            with self.assertRaises(ValueError):quantize_iq(x,gain)
        with self.assertRaises(ValueError):quantize_iq(np.array([complex(float('nan'),0)]),1)

    def test_model_reproduces_existing_hardware_payload(self):
        vectors=ROOT/'sim_vectors/reference_10mhz_gate80'
        def matrix(name):return np.array(read_hex(vectors/(name+'.hex'),48)).reshape(16,16).tolist()
        weights,_=solve_fixed(matrix('cov_re'),matrix('cov_im'),
            read_hex(vectors/'steering_re.hex',24),read_hex(vectors/'steering_im.hex',24))
        ii=np.array(read_hex(vectors/'iq_i.hex',16)).reshape(32,16).T.tolist()
        qq=np.array(read_hex(vectors/'iq_q.hex',16)).reshape(32,16).T.tolist()
        reference=ROOT/'validation/board_20261023/network_rxfix/regression/reference_network_result.hex'
        wire=b''.join(struct.pack('!I',int(w,16)) for w in reference.read_text().split())
        self.assertEqual(beam_fixed(ii,qq,weights),beam_values(decode(wire)))

    def test_conjugate_beam_and_shift_semantics(self):
        # conj(0.5+0.25j)*(3-5j) = 0.25-3.25j, shift floors signed values.
        self.assertEqual(beam_fixed([[3]],[[-5]],[(1<<22,1<<21)]),[(0,-4)])


if __name__=='__main__':unittest.main()
