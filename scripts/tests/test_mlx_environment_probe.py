import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).resolve().parents[1] / 'probe-mlx-environment.py'
spec = importlib.util.spec_from_file_location('mlx_probe', SCRIPT)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class MLXEnvironmentProbeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.distribution = self.root / 'mlx_lm-0.1.dist-info'
        self.distribution.mkdir()
        self.metadata = self.distribution / 'METADATA'
        self.metadata.write_text('Name: mlx-lm\nVersion: 0.1\n')

    def test_metadata_never_grants_runtime_approval(self):
        result = probe.report([self.root])
        self.assertEqual(result['packages']['mlx-lm'], ['0.1'])
        self.assertNotIn('mlx-lm', result['notObserved'])
        self.assertIn('mlx', result['notObserved'])
        self.assertFalse(result['runtimeEnabled'])

    def test_packages_and_startup_hooks_are_not_executed(self):
        package = self.root / 'mlx_lm'
        package.mkdir()
        (package / '__init__.py').write_text('raise RuntimeError("Must never import")')
        sentinel = self.root / 'executed'
        hook = self.root / 'startup.pth'
        hook.write_text(f'import pathlib; pathlib.Path({str(sentinel)!r}).touch()')
        result = probe.report([self.root])
        self.assertEqual(result['startupHooks'], [str(hook)])
        self.assertFalse(sentinel.exists())
        self.assertFalse(result['runtimeEnabled'])

    def test_symlink_metadata_is_unverified_not_missing(self):
        self.metadata.unlink()
        target = self.root / 'external-metadata'
        target.write_text('Name: mlx-lm\nVersion: 9.9\n')
        self.metadata.symlink_to(target)
        result = probe.report([self.root])
        self.assertEqual(result['packages']['mlx-lm'], [])
        self.assertNotIn('mlx-lm', result['notObserved'])
        self.assertTrue(result['issues'])

    def test_oversized_metadata_is_rejected(self):
        self.metadata.write_bytes(b'x' * (probe.MAX_METADATA + 1))
        result = probe.report([self.root])
        self.assertEqual(result['packages']['mlx-lm'], [])
        self.assertTrue(result['issues'])


if __name__ == '__main__':
    unittest.main()
