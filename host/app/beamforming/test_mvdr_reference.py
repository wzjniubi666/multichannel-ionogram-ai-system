import unittest

import numpy as np

from mvdr_reference import beam_output, mvdr_weights, steering_vector, ula_positions


class MvdrReferenceTest(unittest.TestCase):
    def test_covariance_is_hermitian(self):
        rng = np.random.default_rng(7)
        x = rng.normal(size=(4, 128)) + 1j * rng.normal(size=(4, 128))
        r = x @ x.conj().T / x.shape[1]
        np.testing.assert_allclose(r, r.conj().T, rtol=1e-12, atol=1e-12)

    def test_constraint_and_interference_rejection(self):
        rng = np.random.default_rng(11)
        n, k = 8, 4096
        positions = ula_positions(n)
        target = steering_vector(positions, 0.0)
        interferer = steering_vector(positions, 30.0)
        target_samples = rng.normal(size=k) + 1j * rng.normal(size=k)
        interference_samples = 8.0 * (rng.normal(size=k) + 1j * rng.normal(size=k))
        noise = 0.05 * (rng.normal(size=(n, k)) + 1j * rng.normal(size=(n, k)))
        x = target[:, None] * target_samples + interferer[:, None] * interference_samples + noise
        weights, _, _ = mvdr_weights(x, target, loading=0.01)
        self.assertAlmostEqual(abs(np.vdot(weights, target)), 1.0, places=10)
        desired = np.vdot(weights, target)
        nulled = np.vdot(weights, interferer)
        self.assertLess(abs(nulled), 0.05 * abs(desired))
        output = beam_output(weights, x)
        self.assertEqual(output.shape, (k,))


if __name__ == "__main__":
    unittest.main()
