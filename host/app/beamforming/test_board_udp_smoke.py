import socket
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from board_udp_smoke import prepare, transact
from udp_replay import ACK, Packet


class FakeSocket:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.sent = []

    def send(self, data):
        self.sent.append(data)
        return len(data)

    def recv(self, size):
        item = next(self.replies)
        if isinstance(item, Exception):
            raise item
        return item


class BoardSmokeTests(unittest.TestCase):
    def setUp(self):
        self.cfg, self.iq, self.expected = prepare(0x88776655)
        self.ack = Packet(ACK, 0, self.cfg.config_id, self.cfg.frequency_index, self.cfg.gate_index).encode()

    def test_real_reference_transaction(self):
        sock = FakeSocket([self.ack, self.expected.encode()])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = transact(sock, output, self.cfg, self.iq, self.expected)
            self.assertTrue(result['passed'])
            self.assertEqual(len(result['beam']), 32)
            self.assertEqual((output / 'result.bin').read_bytes(), self.expected.encode())
        self.assertEqual(sock.sent, [p.encode() for p in [self.cfg, *self.iq]])

    def test_one_wrong_bit_is_rejected(self):
        data = bytearray(self.expected.payload)
        data[3] ^= 1
        wrong = replace(self.expected, payload=bytes(data))
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with self.assertRaisesRegex(ValueError, 'BOARD_RESULT_MISMATCH'):
                transact(FakeSocket([self.ack, wrong.encode()]), output, self.cfg, self.iq, self.expected)
            self.assertTrue((output / 'failure.json').exists())
            self.assertFalse((output / 'result.bin').exists())

    def test_stale_result_and_ack_timeout(self):
        wrong = replace(self.expected, frame_id=12)
        for replies, marker in [([self.ack, wrong.encode()], 'metadata'),
                                ([socket.timeout('no ACK')], 'no ACK')]:
            sock = FakeSocket(replies)
            with self.subTest(marker=marker), tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex((ValueError, socket.timeout), marker):
                    transact(sock, Path(directory), self.cfg, self.iq, self.expected)
            if marker == 'no ACK':
                self.assertEqual(len(sock.sent), 1)  # No IQ and no automatic retry.


if __name__ == '__main__':
    unittest.main()
