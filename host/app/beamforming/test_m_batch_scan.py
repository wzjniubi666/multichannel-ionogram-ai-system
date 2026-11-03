from pathlib import Path
from dataclasses import replace
from contextlib import closing
import json
import shutil
import socket
import sqlite3
import tempfile
import unittest
from types import SimpleNamespace
import numpy as np
from m_batch_plan import ScanPlan,integers
from m_batch_scan import scan,Journal,EmulatedSocket,requests
from udp_replay import decode

ROOT=Path(__file__).resolve().parents[1]
PLAN=ROOT/'validation/m_batch_20261026/smoke_plan_v2'


def result_data(path):
    with np.load(path) as data:return {key:data[key] for key in data.files}


class FaultSocket(EmulatedSocket):
    def __init__(self,kind):self.kind=kind;self.selected=0
    def select(self,cfg,iq,result):
        super().select(cfg,iq,result);self.selected+=1
        if self.kind=='bit':
            data=bytearray(self.responses[-1]);data[-1]^=1;self.responses[-1]=bytes(data)
        if self.kind=='stale':
            ack=decode(self.responses[0]);self.responses[0]=replace(ack,config_id=ack.config_id^1).encode()
    def recv(self,size):
        if self.kind=='timeout' and self.selected==2 and len(self.responses)==1:
            raise socket.timeout('injected result timeout')
        return super().recv(size)


class BatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (PLAN/'plan.json').exists():raise unittest.SkipTest('prepare real-M smoke scan plan first')
        cls.plan=ScanPlan(PLAN)

    def test_coordinates_and_protocol_location(self):
        self.assertEqual(integers('0:13:4'),[0,4,8,12])
        for bad in ('2,1','0:4:0','0,0'):
            with self.assertRaises(ValueError):integers(bad)
        cfg,iq,result=requests(self.plan,4,0x4D900000)
        self.assertEqual((cfg.frequency_index,cfg.gate_index),(6,80))
        self.assertEqual([p.index for p in iq],[0,1])
        self.assertEqual(len(result.payload),384)

    def test_nine_frame_scan_aggregates_measured_packets(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan'
            summary=scan(self.plan,out,EmulatedSocket(),'emulator',nonce=100,render=False)
            self.assertEqual(summary['status'],'COMPLETE_EMULATOR')
            self.assertFalse(summary['hardware_measurements'])
            data=result_data(out/'scan_results.npz')
            self.assertTrue(data['pixel_complete'].all())
            for ordinal in range(9):
                fp,lp,bp=self.plan.coordinate(ordinal)
                expected=self.plan.expected[ordinal].astype(float)/self.plan.gains[fp,lp]
                np.testing.assert_allclose(data['power'][fp,lp],np.mean((expected**2).sum(axis=1)))
            with closing(sqlite3.connect(out/'scan.sqlite3')) as db:
                self.assertEqual(db.execute("SELECT count(*) FROM attempts WHERE status='VERIFIED'").fetchone()[0],9)

    def test_timeout_partial_then_resume_has_no_duplicates(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan'
            with self.assertRaises(socket.timeout):scan(self.plan,out,FaultSocket('timeout'),'emulator',nonce=10,render=False)
            data=result_data(out/'scan_results.npz')
            self.assertEqual(int(data['pixel_complete'].sum()),1)
            self.assertEqual(int(np.isnan(data['power']).sum()),8)
            summary=scan(self.plan,out,EmulatedSocket(),'emulator',True,nonce=200,render=False)
            self.assertEqual((summary['verified_frames'],summary['attempts']),(9,10))
            with closing(sqlite3.connect(out/'scan.sqlite3')) as db:
                self.assertEqual(db.execute('SELECT frame_id FROM attempts WHERE id=1').fetchone()[0],11)

    def test_corrupt_result_or_stale_ack_stops_and_preserves_raw_data(self):
        for kind,marker,sent in [('bit','BATCH_RESULT_MISMATCH',3),('stale','metadata',1)]:
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
                out=Path(d)/'scan'
                with self.assertRaisesRegex(ValueError,marker):scan(self.plan,out,FaultSocket(kind),'emulator',nonce=10,render=False)
                data=result_data(out/'scan_results.npz')
                self.assertTrue(np.isnan(data['power']).all())
                with closing(sqlite3.connect(out/'scan.sqlite3')) as db:
                    row=db.execute('SELECT status,sent_count,received_1,received_2 FROM attempts').fetchone()
                    self.assertEqual(row[:2],('FAILED',sent));self.assertIsNotNone(row[2])
                    if kind=='bit':self.assertIsNotNone(row[3])

    def test_resume_requires_same_mode_and_explicit_flag(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan'
            scan(self.plan,out,EmulatedSocket(),'emulator',nonce=100,limit=1,render=False)
            with self.assertRaises(FileExistsError):Journal(out,self.plan,'emulator')
            with self.assertRaisesRegex(ValueError,'mismatch'):Journal(out,self.plan,'hardware',True)
            with self.assertRaisesRegex(ValueError,'labelled hardware'):scan(self.plan,Path(d)/'bad',EmulatedSocket(),'hardware',render=False)

    def test_pending_attempt_does_not_count_as_a_result(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan';j=Journal(out,self.plan,'emulator')
            cfg,iq,result=requests(self.plan,0,10);j.begin(0,10,cfg,iq,result);j.close()
            summary=scan(self.plan,out,EmulatedSocket(),'emulator',True,nonce=100,render=False)
            self.assertEqual((summary['verified_frames'],summary['attempts']),(9,10))

    def test_prepared_data_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            v=Path(d)/'plan';shutil.copytree(PLAN,v)
            with (v/'gains.npy').open('r+b') as f:f.seek(-1,2);b=f.read(1);f.seek(-1,2);f.write(bytes([b[0]^1]))
            with self.assertRaisesRegex(ValueError,'prepared file changed'):ScanPlan(v)

    def test_saved_packet_tampering_is_rejected_on_resume(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan';scan(self.plan,out,EmulatedSocket(),'emulator',nonce=10,limit=1,render=False)
            with closing(sqlite3.connect(out/'scan.sqlite3')) as db:
                data=bytearray(db.execute('SELECT received_2 FROM attempts').fetchone()[0]);data[-1]^=1
                db.execute('UPDATE attempts SET received_2=?',(bytes(data),))
                db.commit()
            with self.assertRaisesRegex(ValueError,'journal packet mismatch'):
                scan(self.plan,out,EmulatedSocket(),'emulator',True,render=False)

    def test_nonempty_output_and_concurrent_writer_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan';out.mkdir();(out/'beam_records.csv').write_text('keep')
            with self.assertRaises(FileExistsError):Journal(out,self.plan,'emulator')
            self.assertEqual((out/'beam_records.csv').read_text(),'keep')
            j=Journal(Path(d)/'other',self.plan,'emulator')
            try:
                with self.assertRaises(sqlite3.OperationalError):Journal(Path(d)/'other',self.plan,'emulator',True)
            finally:j.close()

    def test_synthetic_two_blocks_require_complete_pixel_and_mean_power(self):
        # Pure aggregation fixture, explicitly emulator-only, not a real capture.
        synthetic=SimpleNamespace(path=Path('synthetic-two-block-fixture'),hash='synthetic-test',
            nf=1,nl=1,nb=2,meta=dict(frames=2,frequency_mhz=[10],source_frequency_index=[6],
                relative_lag_samples=[80],record_starts=[0,32],profile=dict(sample_period_us=25.6)),
            iq=np.zeros((2,32,16,2),np.int16),steering=np.ones((1,16,2),np.int32),
            gains=np.array([[2.]]),expected=np.zeros((2,32,2),np.int64),
            coordinate=lambda ordinal:(0,0,ordinal))
        synthetic.expected[0,:,0]=2;synthetic.expected[1,:,0]=6
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/'scan'
            scan(synthetic,out,EmulatedSocket(),'emulator',nonce=1,limit=1,render=False)
            partial=result_data(out/'scan_results.npz')
            self.assertFalse(partial['pixel_complete'][0,0]);self.assertTrue(np.isnan(partial['power'][0,0]))
            scan(synthetic,out,EmulatedSocket(),'emulator',True,nonce=10,render=False)
            complete=result_data(out/'scan_results.npz')
            self.assertTrue(complete['pixel_complete'][0,0])
            self.assertEqual(complete['power'][0,0],5.)  # (1^2+3^2)/2, not mean amplitude squared.


if __name__=='__main__':unittest.main()
