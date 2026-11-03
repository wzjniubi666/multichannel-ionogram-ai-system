from dataclasses import replace
from pathlib import Path
import json
import shutil
import tempfile
import unittest
from board_udp_smoke import prepare,transact
from udp_replay import ACK,Packet

ROOT=Path(__file__).resolve().parents[1]
VECTORS=ROOT/'validation/m_fpga_20261026/m10_lag80_r0_k32/vectors'


class FakeSocket:
    def __init__(self,replies):self.replies=iter(replies);self.sent=[]
    def send(self,data):self.sent.append(data);return len(data)
    def recv(self,size):return next(self.replies)


class MBoardBundleTests(unittest.TestCase):
    def setUp(self):
        if not (VECTORS/'hardware_ready.json').exists():
            self.skipTest('generate and simulate the real M bundle first')

    def test_real_m_bundle_and_exact_transaction(self):
        cfg,iq,expected=prepare(0x4D445566,VECTORS)
        self.assertEqual((cfg.frequency_index,cfg.gate_index),(6,80))
        self.assertEqual(len(expected.payload),384)
        ack=Packet(ACK,0,cfg.config_id,6,80)
        sock=FakeSocket([ack.encode(),expected.encode()])
        with tempfile.TemporaryDirectory() as d:
            self.assertTrue(transact(sock,Path(d),cfg,iq,expected)['passed'])
        self.assertEqual(sock.sent,[p.encode() for p in [cfg,*iq]])

    def test_altered_input_vector_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            v=Path(d)/'vectors';shutil.copytree(VECTORS,v)
            p=v/'iq_q.hex';lines=p.read_text().splitlines();lines[7]=f'{int(lines[7],16)^1:04x}'
            p.write_text('\n'.join(lines)+'\n',encoding='ascii')
            with self.assertRaisesRegex(ValueError,'vector changed'):prepare(42,v)

    def test_unverified_or_changed_manifest_rejected(self):
        for which in ('status','manifest'):
            with self.subTest(which=which),tempfile.TemporaryDirectory() as d:
                v=Path(d)/'vectors';shutil.copytree(VECTORS,v)
                if which=='status':
                    p=v/'hardware_ready.json';m=json.loads(p.read_text());m['status']='UNVERIFIED'
                else:
                    p=v/'manifest.json';m=json.loads(p.read_text());m['record_start']=32
                p.write_text(json.dumps(m),encoding='utf-8')
                with self.assertRaises(ValueError):prepare(42,v)

    def test_real_m_wrong_result_bit_rejected(self):
        cfg,iq,expected=prepare(42,VECTORS)
        ack=Packet(ACK,0,cfg.config_id,6,80)
        bad=bytearray(expected.payload);bad[-1]^=1
        sock=FakeSocket([ack.encode(),replace(expected,payload=bytes(bad)).encode()])
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError,'BOARD_RESULT_MISMATCH'):
                transact(sock,Path(d),cfg,iq,expected)
            self.assertTrue((Path(d)/'failure.json').exists())


if __name__=='__main__':unittest.main()
