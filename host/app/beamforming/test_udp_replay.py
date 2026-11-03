import struct
import unittest
from udp_replay import *


class CodecTests(unittest.TestCase):
    def setUp(self):
        self.cfg = configuration([-8388608, 8388607] * 8, [0, -1] * 8, 0x10203040, 160, 80)
        self.packets = iq_packets([-32768, 32767] * 256, [0, -1] * 256, 0x12345678, self.cfg.config_id, 160, 80)

    def test_roundtrip_and_wire_order(self):
        for p in [self.cfg, *self.packets]:
            self.assertEqual(decode(p.encode()), p)
        self.assertEqual(HEADER.size, 32)
        self.assertEqual(self.packets[0].payload[:8], bytes.fromhex("800000007fffffff"))
        self.assertEqual(self.cfg.payload[:12], bytes.fromhex("8000000000007fffffffffff"))
        self.assertEqual([len(p.encode()) for p in [self.cfg, *self.packets]], [128, 1056, 1056])

    def test_malformed(self):
        good = self.packets[0].encode()
        for offset in [0, 4, 7, 23, 25, 27, 29, 31]:
            data = bytearray(good); data[offset] ^= 0x40
            with self.subTest(offset=offset), self.assertRaises(ValueError): decode(bytes(data))
        for data in (good[:-1], good[:32], good+b"\0\0\0\0", b""):
            with self.assertRaises(ValueError): decode(data)

    def test_signed_result(self):
        beam = [(-(1<<47), (1<<47)-1), (-1, 0)] * 16
        p = Packet(RESULT, 9, 8, 160, 80, payload=b"".join(signed_bytes(r,48)+signed_bytes(i,48) for r,i in beam))
        self.assertEqual(beam_values(decode(p.encode())), beam)
        with self.assertRaises(OverflowError): signed_bytes(32768,16)
        with self.assertRaises(ValueError): iq_packets([0], [0], 1,2,3,4)

    def test_host_handshake_and_errors(self):
        class FakeSocket:
            def __init__(self, responses): self.responses=iter(responses); self.sent=[]
            def send(self,data): self.sent.append(data); return len(data)
            def recv(self,size): return next(self.responses)
        ack = Packet(ACK,0,self.cfg.config_id,160,80).encode()
        result = Packet(RESULT,self.packets[0].frame_id,self.cfg.config_id,160,80,payload=bytes(384))
        sock = FakeSocket([ack,result.encode()])
        self.assertEqual(exchange(sock,self.cfg,self.packets),result)
        self.assertEqual(sock.sent,[p.encode() for p in [self.cfg,*self.packets]])
        err = Packet(ERROR,self.packets[0].frame_id,self.cfg.config_id,160,80,status=7).encode()
        with self.assertRaisesRegex(RuntimeError,"SOLVER"): exchange(FakeSocket([ack,err]),self.cfg,self.packets)
        stale = Packet(RESULT,99,self.cfg.config_id,160,80,payload=bytes(384)).encode()
        with self.assertRaisesRegex(ValueError,"metadata"): exchange(FakeSocket([ack,stale]),self.cfg,self.packets)
        with self.assertRaisesRegex(ValueError,"sequence"): exchange(FakeSocket([]),self.cfg,list(reversed(self.packets)))


if __name__ == "__main__": unittest.main()
