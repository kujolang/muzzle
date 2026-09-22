#!/usr/bin/env python3
"""Behavioral regression gates for the September hardening pass (stdlib only)."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get('MUZZLE_TEST_ROOT', Path(__file__).resolve().parents[1])).resolve()


class HardeningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='muzzle-hardening-')
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        self.run_cli('init')

    def run_cli(self, *args, code=0):
        result = subprocess.run([str(ROOT / 'muzzle'), *args], cwd=self.project,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertEqual(result.stderr, '')
        return result.stdout

    def test_redaction_before_tail_and_full_evidence(self):
        kinds = ['PRIVATE KEY', 'RSA PRIVATE KEY', 'OPENSSH PRIVATE KEY',
                 'EC PRIVATE KEY', 'DSA PRIVATE KEY', 'PGP PRIVATE KEY BLOCK',
                 'ENCRYPTED PRIVATE KEY', 'CERTIFICATE', 'ENCRYPTED DATA']
        for kind in kinds:
            for closed in (False, True):
                with self.subTest(kind=kind, closed=closed):
                    output = f'-----BEGIN {kind}-----\n' + 'PRIVATE-BODY\n' * 80
                    if closed:
                        output += f'-----END {kind}-----\nuseful failure detail\n'
                    (self.project / 'payload').write_text(output)
                    (self.project / '.muzzle/workflows/secret.sh').write_text('cat payload\nexit 4\n')
                    summary = json.loads(self.run_cli('run', 'secret', '--json', code=4))
                    self.assertNotIn('PRIVATE-BODY', summary['error_excerpt'])
                    self.assertIn('[REDACTED', summary['error_excerpt'])
                    if closed:
                        self.assertIn('useful failure detail', summary['error_excerpt'])
                    self.assertEqual((self.project / summary['log_path']).read_text(), output)
                    report = (self.project / summary['report_path']).read_text()
                    self.assertNotIn('PRIVATE-BODY', report)
        quiet = self.run_cli('run', 'secret', code=4)
        self.assertNotIn('PRIVATE-BODY', quiet)
        self.assertIn('useful failure detail', quiet)

    def test_oversized_lines_are_explicit_and_logs_remain_complete(self):
        output = 'x' * 1048576 + ' TOKEN=PRIVATE-BODY\nlast diagnostic\n'
        (self.project / 'payload').write_text(output)
        (self.project / '.muzzle/workflows/secret.sh').write_text('cat payload\nexit 4\n')
        summary = json.loads(self.run_cli('run', 'secret', '--json', code=4))
        self.assertNotIn('PRIVATE-BODY', summary['error_excerpt'])
        self.assertIn('last diagnostic', summary['error_excerpt'])
        self.assertLess(len(summary['error_excerpt']), 1000)
        self.assertEqual((self.project / summary['log_path']).read_text(), output)
        (self.project / 'payload').write_text('x' * 1048576 + '\nlast diagnostic')
        summary = json.loads(self.run_cli('run', 'secret', '--json', code=4))
        self.assertIn('Oversized log line omitted', summary['error_excerpt'])
        self.assertIn('last diagnostic', summary['error_excerpt'])

    def test_loop_json_idempotence_and_invalid_entries(self):
        first = json.loads(self.run_cli('loop', 'start', 'hello', '--limit', '2', '--json'))
        again = json.loads(self.run_cli('loop', 'start', 'hello', '--limit', '8', '--json'))
        self.assertEqual(first, again)
        state_file = self.project / '.muzzle/state/loops/hello.json'
        original = json.loads(state_file.read_text())
        invalid_entries = [None, 'invalid', {}, {'loop': '1', 'status': 'done', 'note': '', 'timestamp': ''},
                           {'loop': 99, 'status': 'done', 'note': '', 'timestamp': ''}]
        for entry in invalid_entries:
            with self.subTest(entry=entry):
                state = dict(original, entries=[entry])
                content = json.dumps(state)
                state_file.write_text(content)
                result = json.loads(self.run_cli('loop', 'status', '--json', code=1))
                self.assertEqual(result['code'], 'LOOP_STATE_INVALID')
                self.assertEqual(state_file.read_text(), content)

    def test_snapshot_batching_preserves_paths_and_denies_link_failure(self):
        workflows = self.project / '.muzzle/workflows'
        nested = workflows / 'nested space'
        nested.mkdir()
        for index in range(130):
            (self.project / f'entry-{index}').touch()
            (nested / f'entry-{index}').touch()
        for name in ['.hidden', '..hidden', 'space name', 'line\nbreak', '-option']:
            (nested / name).write_text('sibling')
        (nested / 'dangling').symlink_to('missing')
        script = nested / 'probe.sh'
        script.write_text('''set -euo pipefail
here="${BASH_SOURCE[0]%/*}"
for name in .hidden ..hidden 'space name' $'line\\nbreak' -option; do
  [[ "$(cat "$here/$name")" == sibling ]]
done
[[ -L "$here/dangling" && ! -e "$here/dangling" ]]
[[ -f "$here/../../../entry-129" ]]
printf 'snapshot-ok\\n'
''')
        shim = self.project / 'shim'
        shim.mkdir()
        count = self.project / 'ln-count'
        real_ln = subprocess.check_output(['which', 'ln'], text=True).strip()
        (shim / 'ln').write_text(f'#!/bin/bash\nprintf "call\\n" >> "$LN_COUNT"\nexec "{real_ln}" "$@"\n')
        (shim / 'ln').chmod(0o755)
        env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'], LN_COUNT=str(count))
        command = ['bash', str(ROOT / 'src/muzzle_exec.sh'), 'bash', '.muzzle/workflows/nested space/probe.sh',
                   hashlib.sha256(script.read_bytes()).hexdigest(), '.muzzle/state/executions/' + 'a' * 32,
                   '.muzzle/logs/probe.log', 'false', os.environ.get('KUJO_BIN', 'kujo'), '--']
        result = subprocess.run(command, cwd=self.project, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.project / '.muzzle/logs/probe.log').read_text(), 'snapshot-ok\n')
        self.assertLessEqual(len(count.read_text().splitlines()), 10)
        self.assertEqual(list((self.project / '.muzzle/state/executions').iterdir()), [])
        (shim / 'ln').write_text('#!/bin/bash\nexit 77\n')
        result = subprocess.run(command, cwd=self.project, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual((self.project / '.muzzle/logs/probe.log').read_text(), '')
        self.assertEqual(list((self.project / '.muzzle/state/executions').iterdir()), [])

    def test_lint_does_not_mask_an_earlier_failure(self):
        stub = self.project / 'kujo-stub'
        stub.write_text('#!/bin/sh\ncase "$2" in src/cli.kujo) exit 37;; esac\nexit 0\n')
        stub.chmod(0o755)
        result = subprocess.run(['make', 'lint', f'KUJO_BIN={stub}'], cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_discovery_names_and_regular_file_boundary(self):
        workflows = self.project / '.muzzle/workflows'
        (workflows / 'build.sh.sh').write_text("echo suffix-ok\n")
        (workflows / 'directory.sh').mkdir()
        (workflows / 'escape.sh').symlink_to(self.project / 'outside.sh')
        (self.project / 'outside.sh').write_text('echo outside\n')
        manifest = dict(name='alias.json', runner='bash', script='workflows/build.sh.sh')
        (self.project / '.muzzle/manifests/alias.json.json').write_text(json.dumps(manifest))
        listing = json.loads(self.run_cli('list', '--json'))
        names = [row['name'] for row in listing['workflows']]
        self.assertIn('build.sh', names)
        self.assertIn('alias.json', names)
        self.assertNotIn('directory', names)
        self.assertNotIn('escape', names)
        self.run_cli('run', 'build.sh', '--json')
        self.run_cli('run', 'alias.json', '--json')
        denial = json.loads(self.run_cli('run', 'directory', '--json', code=1))
        self.assertEqual(denial['code'], 'WORKFLOW_SCRIPT_UNSAFE')
        (self.project / '.muzzle/manifests/unreadable.json').mkdir()
        denial = json.loads(self.run_cli('info', 'unreadable', '--json', code=2))
        self.assertEqual(denial['code'], 'MANIFEST_READ')


if __name__ == '__main__':
    unittest.main()
