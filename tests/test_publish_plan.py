"""Fixture tests for stable package and image reconciliation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SELECT = Path(__file__).with_name('select-package.py')


class PublishPlan(unittest.TestCase):
    def plan(self, labels=None, force='', mismatch=False, empty=False, inspect_error=None, api_error=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for arch in ('amd64', 'arm64'):
                entries = [('gel-server-6', '1:6.10-2'), ('gel-server-7', '1:7.9-1'),
                           ('gel-server-7', '1:7.10-1'), ('gel-cli', '1:7.2-1')]
                if mismatch and arch == 'arm64':
                    entries[-1] = ('gel-cli', '1:7.1-1')
                (root / arch).write_text(''.join(f'Package: {name}\nVersion: {version}\nArchitecture: {arch}\n\n' for name, version in entries) if not empty else '')
            (root / 'labels').write_text(json.dumps(labels or {}))
            env = os.environ.copy()
            label_args = ['--labels', str(root / 'labels')]
            if inspect_error is not None:
                label_args = []
                for name, error in [('docker', inspect_error), ('gh', api_error)]:
                    executable = root / name
                    executable.write_text(f'#!{sys.executable}\nimport sys\nsys.stderr.write({error!r})\nsys.exit(1)\n')
                    executable.chmod(0o755)
                env['PATH'] = str(root) + os.pathsep + env['PATH']
            result = subprocess.run([sys.executable, str(SELECT), '--all', '--amd64', str(root / 'amd64'), '--arm64', str(root / 'arm64'), '--slot', force] + label_args, capture_output=True, text=True, env=env)
            if api_error and '(HTTP 404)' not in api_error:
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(api_error, result.stderr)
                return
            if mismatch:
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('disagree', result.stderr)
                return
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)['include']

    def current(self):
        return {slot: {'com.gelstable.server-version': version, 'com.gelstable.cli-version': '1:7.2-1'} for slot, version in [('6', '1:6.10-2'), ('7', '1:7.10-1')]}

    def test_new_server_and_missing_tag(self):
        labels = self.current()
        labels['7']['com.gelstable.server-version'] = '1:7.9-1'
        plan = self.plan(labels)
        self.assertEqual(plan, [{'slot': '7', 'version': '1:7.10-1', 'cli_version': '1:7.2-1', 'tags': ['7', '7.10', 'latest']}])
        self.assertEqual([p['slot'] for p in self.plan()], ['6', '7'])

    def test_new_cli_rebuilds_every_slot(self):
        labels = self.current()
        for item in labels.values():
            item['com.gelstable.cli-version'] = '1:7.1-1'
        self.assertEqual([p['slot'] for p in self.plan(labels)], ['6', '7'])

    def test_nothing_new(self):
        self.assertEqual(self.plan(self.current()), [])

    def test_forced_slot(self):
        self.assertEqual(self.plan(self.current(), force='6')[0]['tags'], ['6', '6.10'])

    def test_arch_mismatch(self):
        self.plan(mismatch=True)

    def test_ghcr_first_publication(self):
        error = 'ERROR: failed to authorize: token 403 Forbidden'
        self.assertEqual([p['slot'] for p in self.plan(inspect_error=error, api_error='gh: Package not found. (HTTP 404)')], ['6', '7'])
        self.plan(inspect_error=error, api_error='gh: Bad credentials (HTTP 401)')

    def test_empty_registry(self):
        self.assertEqual(self.plan(empty=True), [])


if __name__ == '__main__':
    unittest.main()
