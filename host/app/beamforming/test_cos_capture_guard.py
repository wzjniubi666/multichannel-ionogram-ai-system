from pathlib import Path
import tempfile
import unittest
import numpy as np

from mvdr_reference import load_cos_gate, load_iq


class CaptureGuardTests(unittest.TestCase):
    def write_capture(self, root, waveform="C", capture="20260602_183600", channels=2):
        for ch in range(channels):
            path = root / f"{waveform},16,2.000_0.050_2.000,8_320_16,{capture},30N_114E,ch_{ch:02d}.cos"
            a = np.arange(32 * 320 * 2, dtype=np.int16).reshape(1, 32, 320, 2) - 1000 + ch
            path.write_bytes(a.astype(">i2").tobytes())

    def test_legacy_c_remains_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_capture(root)
            x = load_cos_gate(root, 2.0, 7, n_ch=2, records=3)
            for ch in range(2):
                for k in range(3):
                    expected = complex(k * 640 + 14 - 1000 + ch, k * 640 + 15 - 1000 + ch)
                    self.assertEqual(x[ch, k], expected)

    def test_raw_m_is_rejected_before_legacy_reshape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_capture(root, waveform="M")
            with self.assertRaisesRegex(ValueError, "actual M-code matched filter"):
                load_cos_gate(root, 2.0, 7, n_ch=2)
            with self.assertRaisesRegex(ValueError, "raw M capture"):
                load_iq(root, n_ch=2, snapshots=32)

    def test_mixed_times_cannot_become_extra_channels(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_capture(root, capture="20260602_183600")
            self.write_capture(root, capture="20260602_184600")
            with self.assertRaisesRegex(ValueError, "duplicate channel"):
                load_iq(root, n_ch=4, snapshots=32)

    def test_root_requires_capture_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "20260714_100000").mkdir()
            with self.assertRaisesRegex(ValueError, "select one capture subdirectory"):
                load_cos_gate(root, 10, 80)


if __name__ == "__main__":
    unittest.main()
