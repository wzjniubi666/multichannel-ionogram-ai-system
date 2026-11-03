from pathlib import Path
from types import SimpleNamespace
import json
import shutil
import tempfile
import unittest
import numpy as np
import test_m_batch_scan as legacy
from m_reference_preprocess import METHOD,load_reference,compress_periods
from m_reference_batch_plan import ReferenceScanPlan
from m_batch_scan import scan,EmulatedSocket
from m_sequence_pipeline import make_chips,MProfile

ROOT=Path(__file__).resolve().parents[1]
PLAN=ROOT/'validation/m_hf32_20261026/network_plan_v2'
REFERENCE=Path('./HFceshi/m255a.mat')


class ReferenceProcessingTests(unittest.TestCase):
    def test_actual_code_is_not_legacy_shift_reversal_or_sign(self):
        actual=load_reference(REFERENCE);old=make_chips(MProfile())
        for other in (old,old[::-1]):
            cross=np.fft.ifft(np.fft.fft(actual)*np.fft.fft(other).conj())
            self.assertLess(float(abs(cross).max()),255-1e-8)

    def test_known_delays_keep_phases_and_periods_separate(self):
        code=load_reference(REFERENCE)
        raw=np.zeros((16,512,1020),complex)
        raw[0,0,2::4]=(2+3j)*np.roll(code,5)
        raw[15,31,1::4]=(-4+1j)*np.roll(code,7)
        compressed=compress_periods(raw,code)
        self.assertEqual(compressed[0,0,4*5+2],255*(2+3j))
        self.assertEqual(compressed[15,31,4*7+1],255*(-4+1j))
        self.assertTrue((compressed[0,1:]==0).all())
        self.assertTrue((compressed[0,0,0::4]==0).all())
        self.assertTrue((compressed[0,0,1::4]==0).all())
        self.assertTrue((compressed[0,0,3::4]==0).all())
        self.assertEqual(compressed[0,0,4*6+2],-(2+3j))
        # This direct independent reference rejects deliberate wrong lag/phase expectations.
        self.assertNotEqual(compressed[0,0,4*5+1],255*(2+3j))
        self.assertNotEqual(compressed[0,0,4*6+2],255*(2+3j))

    def test_prepared_iq_equals_exact_integer_dot_for_all16_channels(self):
        plan=ReferenceScanPlan(PLAN)
        code=load_reference(REFERENCE).astype(np.int64)
        for ordinal in range(9):
            fp,lp,_=plan.coordinate(ordinal);fi=plan.meta['source_frequency_index'][fp]
            chip,phase=divmod(plan.meta['relative_lag_samples'][lp],4)
            shifted=np.roll(code,chip)
            for channel,row in enumerate(plan.meta['source']):
                data=np.memmap(row['path'],dtype='>i2',mode='r',shape=(41,512,255,4,2))
                for period in (0,31):
                    iq=data[fi,period,:,phase,:].astype(np.int64)
                    exact=iq.T@shifted
                    wanted=np.rint(exact*plan.gains[fp,lp]).astype(np.int16)
                    np.testing.assert_array_equal(plan.iq[ordinal,period,channel],wanted)

    def test_old_plan_rejected_by_actual_reference_entry(self):
        with self.assertRaisesRegex(ValueError,'legacy M plan rejected'):
            ReferenceScanPlan(ROOT/'validation/m_batch_20261026/smoke_plan_v2')

    def test_reference_snapshot_tampering_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'plan';shutil.copytree(PLAN,target)
            file=target/'reference_snapshot/m255a.mat'
            content=bytearray(file.read_bytes());content[-1]^=1;file.write_bytes(content)
            with self.assertRaisesRegex(ValueError,'prepared file changed'):
                ReferenceScanPlan(target)

    def test_coherent32_cancellation_and_blocks_are_not_cross_summed(self):
        fake=SimpleNamespace(path=Path('synthetic-reference-aggregation'),hash='synthetic-not-hardware',
            nf=1,nl=1,nb=2,meta=dict(frames=2,frequency_mhz=[10],source_frequency_index=[6],
                relative_lag_samples=[80],record_starts=[0,32],profile=dict(sample_period_us=25.6),
                preprocessing=METHOD,reference_files_sha256={'m255a.mat':'synthetic'}),
            iq=np.zeros((2,32,16,2),np.int16),steering=np.ones((1,16,2),np.int32),
            gains=np.array([[2.]]),expected=np.zeros((2,32,2),np.int64),coordinate=lambda i:(0,0,i))
        fake.expected[0,:,0]=np.tile([2,-2],16);fake.expected[1,:,0]=2
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan'
            scan(fake,out,EmulatedSocket(),'emulator',nonce=5,limit=1,render=False)
            with np.load(out/'scan_results.npz') as data:
                self.assertTrue(np.isnan(data['coherent_power'][0,0]))
                self.assertEqual(data['coherent_sum_re_rescaled'][0,0,0],0)
            summary=scan(fake,out,EmulatedSocket(),'emulator',True,nonce=10,render=False)
            self.assertFalse(summary['hardware_measurements'])
            with np.load(out/'scan_results.npz') as data:
                self.assertEqual(data['power'][0,0],1)
                self.assertEqual(data['coherent_power'][0,0],512)
                self.assertAlmostEqual(data['reference_script_range_km'][0],81*7.68)


class CorrectedTransportTests(legacy.BatchTests):
    @classmethod
    def setUpClass(cls):cls.plan=ReferenceScanPlan(PLAN)

    def test_prepared_data_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'plan';shutil.copytree(PLAN,target)
            file=target/'gains.npy'
            content=bytearray(file.read_bytes());content[-1]^=1;file.write_bytes(content)
            with self.assertRaisesRegex(ValueError,'prepared file changed'):ReferenceScanPlan(target)


if __name__=='__main__':unittest.main()
