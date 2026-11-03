from pathlib import Path
from dataclasses import replace
from contextlib import closing
import socket
import sqlite3
import tempfile
import unittest
import numpy as np
from udp512 import Packet512,IQ_ACK,decode,configuration,iq_packets,result_packets,beam_values,exchange,ACK,RESULT
from udp_replay import decode as decode32
from m512_plan import Plan512
from m512_packets import requests
from m512_scan import scan,Journal512,Emulated512Socket,unpack_packets,audit_rows

ROOT=Path(__file__).resolve().parents[1]
PLAN=ROOT/'validation/m_hf512_20261026/network_plan_v1'


class Fault512(Emulated512Socket):
    def __init__(self,kind):self.kind=kind;self.calls=0
    def select(self,cfg,iq,results):
        super().select(cfg,iq,results);self.calls+=1
        if self.kind=='bit':
            value=bytearray(self.responses[-1]);value[-1]^=1;self.responses[-1]=bytes(value)
        elif self.kind=='duplicate':self.responses[-1]=self.responses[-2]
        elif self.kind=='stale':
            value=decode(self.responses[1]);self.responses[1]=replace(value,config_id=value.config_id^1).encode()
    def recv(self,size):
        if self.kind=='timeout' and self.calls==2 and len(self.responses)==8:raise socket.timeout('injected halfway result timeout')
        return super().recv(size)


class Joint512Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.plan=Plan512(PLAN)

    def test_codec_all_packet_counts_and_512_record_boundaries(self):
        re=[-32768,32767]*4096;im=list(reversed(re))
        iq=iq_packets(re,im,9,10,1,148)
        self.assertEqual(len(iq),32)
        for index,packet in enumerate(iq):
            self.assertEqual(decode(packet.encode()),packet)
            self.assertEqual((packet.index,packet.count,len(packet.payload)),(index,32,1024))
        decoded=b''.join(packet.payload for packet in iq)
        values=np.frombuffer(decoded,dtype='>i2').reshape(512,16,2)
        self.assertEqual(values[511,15].tolist(),[32767,-32768])
        result=result_packets([(-(1<<47)+k,(1<<47)-1-k) for k in range(512)],9,10,1,148)
        self.assertEqual(len(result),16)
        self.assertEqual(beam_values(decode(result[-1].encode()))[-1],(-(1<<47)+511,(1<<47)-1-511))
        with self.assertRaises(ValueError):decode32(iq[0].encode())
        raw=bytearray(iq[0].encode());raw[4]=1
        with self.assertRaises(ValueError):decode(bytes(raw))

    def test_real_joint512_inputs_match_previous32_prefix_without_accumulating(self):
        from m_reference_batch_plan import ReferenceScanPlan
        old=ReferenceScanPlan(ROOT/'validation/m_hf32_20261026/scan41x118_r0_v2')
        for ordinal in range(9):
            fp,lp,_=self.plan.coordinate(ordinal)
            source_f=self.plan.meta['source_frequency_index'][fp];lag=self.plan.meta['relative_lag_samples'][lp]
            old_lp=old.meta['relative_lag_samples'].index(lag);old_ordinal=source_f*old.nl+old_lp
            self.assertEqual(self.plan.gains[fp,lp],old.gains[source_f,old_lp])
            np.testing.assert_array_equal(self.plan.iq[ordinal,:32],old.iq[old_ordinal])

    def test_strict_ack_then_iq_then16_result_exchange(self):
        cfg,iq,result=requests(self.plan,4,0x51210000)
        sock=Emulated512Socket();sock.select(cfg,iq,result)
        self.assertEqual(exchange(sock,cfg,iq),result)
        self.assertEqual(sock.position,33);self.assertFalse(sock.responses)
        with self.assertRaises(ValueError):exchange(sock,cfg,list(reversed(iq)))

    def test_completed_scan_has512_outputs_and_one_coherent_sum(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan';summary=scan(self.plan,out,Emulated512Socket(),'emulator',nonce=100,render=False)
            self.assertEqual(summary['status'],'COMPLETE_EMULATOR');self.assertTrue(summary['joint_512_record_weights'])
            with np.load(out/'scan_results.npz') as data:
                self.assertEqual(data['beam_re_rescaled'].shape,(3,3,512))
                for ordinal in range(9):
                    fp,lp,_=self.plan.coordinate(ordinal)
                    pairs=self.plan.expected[ordinal].astype(float)/self.plan.gains[fp,lp]
                    wanted=abs(complex(pairs[:,0].sum(),pairs[:,1].sum()))**2
                    self.assertAlmostEqual(data['coherent_power'][fp,lp]/max(wanted,1),wanted/max(wanted,1),places=12)

    def test_partial_result_timeout_keeps_raw_and_resume_replays_only_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan'
            with self.assertRaises(socket.timeout):scan(self.plan,out,Fault512('timeout'),'emulator',nonce=100,render=False)
            with np.load(out/'scan_results.npz') as data:
                self.assertEqual(int(data['pixel_complete'].sum()),1);self.assertEqual(int(np.isnan(data['coherent_power']).sum()),8)
            with closing(sqlite3.connect(out/'scan.sqlite3')) as db:
                received=db.execute("SELECT received FROM attempts WHERE status='FAILED'").fetchone()[0]
                self.assertEqual(len(unpack_packets(received)),41)
            summary=scan(self.plan,out,Emulated512Socket(),'emulator',True,nonce=200,render=False)
            self.assertEqual((summary['verified_frames'],summary['attempts']),(9,10))

    def test_stale_duplicate_and_bit_corruption_never_commit(self):
        for kind in ('stale','duplicate','bit'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as directory:
                out=Path(directory)/'scan'
                with self.assertRaises(ValueError):scan(self.plan,out,Fault512(kind),'emulator',nonce=100,render=False)
                with np.load(out/'scan_results.npz') as data:self.assertFalse(data['pixel_complete'].any())

    def test_pending_is_not_measurement_and_emulator_cannot_be_hardware(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan';journal=Journal512(out,self.plan,'emulator')
            cfg,iq,result=requests(self.plan,0,100);journal.begin(0,100,cfg,iq,result);journal.close()
            summary=scan(self.plan,out,Emulated512Socket(),'emulator',True,nonce=200,render=False)
            self.assertEqual((summary['verified_frames'],summary['attempts']),(9,10))
            with self.assertRaisesRegex(ValueError,'cannot be labelled'):scan(self.plan,Path(directory)/'bad',Emulated512Socket(),'hardware',render=False)

    def test_same_mode_plan_and_explicit_resume_required(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan';scan(self.plan,out,Emulated512Socket(),'emulator',nonce=100,limit=1,render=False)
            with self.assertRaises(FileExistsError):Journal512(out,self.plan,'emulator')
            with self.assertRaisesRegex(ValueError,'mismatch'):Journal512(out,self.plan,'hardware',True)

    def test_raw_result_tampering_rejected_on_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan';scan(self.plan,out,Emulated512Socket(),'emulator',nonce=100,limit=1,render=False)
            with closing(sqlite3.connect(out/'scan.sqlite3')) as db:
                raw=bytearray(db.execute('SELECT received FROM attempts').fetchone()[0]);raw[-1]^=1
                db.execute('UPDATE attempts SET received=?',(bytes(raw),));db.commit()
            with self.assertRaisesRegex(ValueError,'saved packet mismatch'):scan(self.plan,out,Emulated512Socket(),'emulator',True,render=False)

    def test_legacy_plan_and_partial_framed_blob_rejected(self):
        with self.assertRaises(ValueError):Plan512(ROOT/'validation/m_hf32_20261026/network_plan_v2')
        for raw in (b'\0',b'\0\0\0\x20',b'\xff'*40):
            with self.assertRaises(ValueError):unpack_packets(raw)

    def test_concurrent_writer_and_nonempty_directory_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'scan';out.mkdir();(out/'keep.txt').write_text('keep')
            with self.assertRaises(FileExistsError):Journal512(out,self.plan,'emulator')
            journal=Journal512(Path(directory)/'other',self.plan,'emulator')
            try:
                with self.assertRaises(sqlite3.OperationalError):Journal512(Path(directory)/'other',self.plan,'emulator',True)
            finally:journal.close()


if __name__=='__main__':unittest.main()
