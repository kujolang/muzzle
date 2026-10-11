#!/usr/bin/env python3
"""Behavioral regression gates for repository hardening (stdlib only)."""
import hashlib
import json
import os
import shutil
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

    def test_loop_missing_note_does_not_corrupt_state(self):
        self.run_cli('loop', 'start', 'hello', '--limit', '1', '--json')
        self.run_cli('loop', 'next', '--json')
        state = self.project / '.muzzle/state/loops/hello.json'
        original = state.read_bytes()
        # Exported state writers also reject values that readers cannot load.
        shutil.copytree(ROOT / 'src', self.project / 'src')
        probe = self.project / 'probe.kujo'
        probe.write_text('from src.loops import record_loop_done\n'
                         'print(to_json(array(\n'
                         'record_loop_done(".muzzle/state/loops/hello.json", true, "now"),\n'
                         'record_loop_done(".muzzle/state/loops/hello.json", "note", false)\n'
                         ')))\n')
        result = subprocess.run([os.environ.get('KUJO_BIN', 'kujo'), 'run', str(probe)],
                                cwd=self.project, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), [False, False])
        self.assertEqual(state.read_bytes(), original)
        for flags in [('--note', '--json'), ('--json', '--note')]:
            with self.subTest(flags=flags):
                state.write_bytes(original)
                result = json.loads(self.run_cli('loop', 'done', *flags, code=2))
                self.assertEqual(result['code'], 'OPTION_VALUE_REQUIRED')
                self.assertEqual(state.read_bytes(), original)
                self.run_cli('loop', 'status', '--json')
        state.write_bytes(original)
        literal = json.loads(self.run_cli('loop', 'done', '--note=--json', '--json'))
        self.assertEqual(literal['note'], '--json')
        self.run_cli('loop', 'next', '--json')
        self.run_cli('loop', 'summary', '--json')

    def test_manifest_no_declared_args_enforces_arity(self):
        manifest_path = self.project / '.muzzle/manifests/hello-bash.json'
        manifest = json.loads(manifest_path.read_text())
        manifest.pop('args', None)
        manifest['allow_extra_args'] = False
        for definitions in [None, []]:
            if definitions is None:
                manifest.pop('args', None)
            else:
                manifest['args'] = definitions
            manifest_path.write_text(json.dumps(manifest))
            for mode in [[], ['--dry-run']]:
                with self.subTest(definitions=definitions, mode=mode):
                    result = json.loads(self.run_cli('run', 'hello-bash', 'unexpected',
                                                     *mode, '--validate-args', '--json', code=2))
                    self.assertEqual(result['code'], 'ARG_ARITY')
                    self.assertEqual(result['details'], {'maximum': 0, 'actual': 1})
            self.run_cli('run', 'hello-bash', '--dry-run', '--validate-args', '--json')
        self.assertEqual(list((self.project / '.muzzle/logs').iterdir()), [])
        # Argument validation remains opt-in.
        self.run_cli('run', 'hello-bash', 'legacy', '--dry-run', '--json')
        manifest.pop('args')
        for allow in [True, None]:
            if allow is None:
                manifest.pop('allow_extra_args', None)
            else:
                manifest['allow_extra_args'] = allow
            manifest_path.write_text(json.dumps(manifest))
            preview = json.loads(self.run_cli('run', 'hello-bash', 'supported', '--dry-run', '--validate-args', '--json'))
            self.assertEqual(preview['args'], ['supported'])

    def test_cleanup_missing_values_never_select_artifacts(self):
        artifact = self.project / ('.muzzle/logs/true-1-' + 'a' * 32 + '.log')
        artifact.write_text('evidence')
        invalid = [('--workflow', '--json'), ('--workflow', '-n', '--json'),
                   ('--workflow=', '--json'), ('--workflow', '', '--json'),
                   ('--keep', '--json'), ('--older-than', '--json')]
        for flags in invalid:
            with self.subTest(flags=flags):
                result = json.loads(self.run_cli('clean', *flags, code=2))
                self.assertIn(result['code'], ['OPTION_VALUE_REQUIRED', 'WORKFLOW_NAME_INVALID'])
                self.assertEqual(artifact.read_text(), 'evidence')
        valid = json.loads(self.run_cli('clean', '--workflow=true', '--keep=0', '--older-than=0', '--json', '-n'))
        self.assertEqual(valid['workflow'], 'true')
        self.assertEqual(valid['selected'], 1)
        self.assertEqual(valid['removed'], 0)
        self.assertEqual(artifact.read_text(), 'evidence')

    def test_json_inspection_flag_preserves_positionals(self):
        for command in ['info', 'show', 'integrity', 'checksum', 'logs', 'log', 'report', 'reports']:
            with self.subTest(command=command):
                before = json.loads(self.run_cli(command, '--json', 'hello-bash'))
                after = json.loads(self.run_cli(command, 'hello-bash', '--json'))
                self.assertEqual(before, after)
        started = json.loads(self.run_cli('loop', '--json', 'start', 'hello', '--limit', '2'))
        self.assertEqual(started['current'], 0)
        self.run_cli('loop', '--json', 'next')
        self.run_cli('loop', '--json', 'done', '--note', 'literal note')
        status = json.loads(self.run_cli('loop', '--json', 'status'))
        self.assertEqual(status['loop']['entries'][0]['note'], 'literal note')

    def test_loop_rejects_unreachable_state_without_mutation(self):
        self.run_cli('loop', 'start', 'hello', '--limit', '3', '--json')
        state = self.project / '.muzzle/state/loops/hello.json'
        original = json.loads(state.read_text())
        invalid = [dict(original, current=2), dict(original, status='completed'),
                   dict(original, workflow='../escape'), dict(original, limit=1001)]
        for value in invalid:
            content = json.dumps(value)
            for command in ['status', 'next', 'summary', 'done']:
                with self.subTest(value=value, command=command):
                    state.write_text(content)
                    result = json.loads(self.run_cli('loop', command, '--json', code=1))
                    self.assertEqual(result['code'], 'LOOP_STATE_INVALID')
                    self.assertEqual(state.read_text(), content)
        state.write_text(json.dumps(original))
        for _ in range(3):
            self.run_cli('loop', 'next', '--json')
            self.run_cli('loop', 'done', '--json')
        completed = json.loads(self.run_cli('loop', 'next', '--json'))
        self.assertEqual(completed['status'], 'completed')
        self.run_cli('loop', 'summary', '--json')

    def test_benchmark_rejects_failed_concurrent_workflows(self):
        real_kujo = subprocess.check_output(['which', os.environ.get('KUJO_BIN', 'kujo')], text=True).strip()
        stub = self.project / 'kujo-stub'
        stub.write_text('#!/bin/bash\nfor arg in "$@"; do\n'
                        '  [[ "$arg" != hello-bash ]] || exit 19\ndone\n'
                        'exec "$REAL_KUJO" "$@"\n')
        stub.chmod(0o755)
        env = dict(os.environ, KUJO_BIN=str(stub), REAL_KUJO=real_kujo,
                   MUZZLE_BENCH_ITERATIONS='2', MUZZLE_BENCH_LINES='1')
        result = subprocess.run(['bash', str(ROOT / 'scripts/benchmark.sh')], cwd=self.project,
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Muzzle local benchmark signal', result.stdout)

    def test_short_cleanup_preview_never_deletes_artifacts(self):
        summary = json.loads(self.run_cli('run', 'hello-bash', '--json'))
        for flags in [('-n', '--json'), ('--json', '-n'), ('--json', '--dry-run')]:
            with self.subTest(flags=flags):
                preview = json.loads(self.run_cli('clean', *flags))
                self.assertTrue(preview['dry_run'])
                self.assertEqual(preview['removed'], 0)
                self.assertEqual(preview['selected'], 3)
                self.assertTrue((self.project / summary['log_path']).is_file())
                self.assertTrue((self.project / summary['report_path']).is_file())

    def test_run_option_values_never_activate_flags(self):
        manifest_path = self.project / '.muzzle/manifests/hello-bash.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['safety']['human_approval_recommended'] = True
        manifest_path.write_text(json.dumps(manifest))
        denied = json.loads(self.run_cli('run', 'hello-bash', '--policy', 'enforce',
                                        '--cancel-file', '--approve', '--json', code=3))
        self.assertEqual(denied['code'], 'POLICY_APPROVAL_REQUIRED')
        self.assertEqual(list((self.project / '.muzzle/logs').iterdir()), [])
        for value in ['--dry-run', '--verbose', '--timeout', '--runner', '--json']:
            with self.subTest(value=value):
                result = json.loads(self.run_cli('run', 'hello-bash', '--cancel-file', value, '--json'))
                self.assertEqual(result['status'], 'success')
                self.assertNotIn('dry_run', result)
        text = self.run_cli('run', 'hello-bash', '--cancel-file', '--json', '--dry-run')
        self.assertIn('[DRY RUN]', text)
        literal = ['--approve', '--json', '--', '', 'a b', '$(literal)']
        preview = json.loads(self.run_cli('run', '--json', '--dry-run', 'hello-bash', '--', *literal))
        self.assertEqual(preview['args'], literal)
        first = json.loads(self.run_cli('execute', 'hello-bash', '--runner', 'bash',
                                       '--runner', 'python', '--json', '--dry-run'))
        self.assertEqual(first['runner'], 'bash')

    def test_policy_snapshot_rejects_external_state(self):
        state = self.project / '.muzzle/state'
        state.rename(self.project / 'original-state')
        outside = self.project / 'outside'
        outside.mkdir()
        state.symlink_to(outside, target_is_directory=True)
        for name in ['bundle.json', 'public.pem', 'signature.bin']:
            (self.project / name).write_text('fixture')
        shim = self.project / 'shim'
        shim.mkdir()
        (shim / 'openssl').write_text('#!/bin/sh\ntouch verifier-called\nexit 1\n')
        (shim / 'openssl').chmod(0o755)
        env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'])
        result = subprocess.run([str(ROOT / 'muzzle'), 'run', 'hello-bash', '--dry-run', '--json',
                                 '--policy-bundle', 'bundle.json', '--policy-public-key', 'public.pem',
                                 '--policy-signature', 'signature.bin'], cwd=self.project,
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['code'], 'POLICY_STATE_UNSAFE')
        self.assertFalse((self.project / 'verifier-called').exists())
        self.assertEqual(list(outside.iterdir()), [])

    def test_cleanup_rejects_symlinked_ancestors(self):
        for ancestor in ['.muzzle', '.muzzle/state', '.muzzle/state/executions']:
            for mode in ['--cleanup', '--cleanup-owner']:
                with self.subTest(ancestor=ancestor, mode=mode):
                    with tempfile.TemporaryDirectory(prefix='muzzle-cleanup-') as temp:
                        project = Path(temp)
                        external = project / 'outside'
                        external.mkdir()
                        link = project / ancestor
                        link.parent.mkdir(parents=True, exist_ok=True)
                        link.symlink_to(external, target_is_directory=True)
                        root = project / '.muzzle/state/executions' / ('a' * 32)
                        root.mkdir(parents=True)
                        (root / '.owner').write_text('12345')
                        (root / 'sentinel').write_text('preserve')
                        arg = str(root.relative_to(project)) if mode == '--cleanup' else '12345'
                        result = subprocess.run(['bash', str(ROOT / 'src/muzzle_exec.sh'), mode, arg],
                                                cwd=project, capture_output=True, text=True)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual((root / 'sentinel').read_text(), 'preserve')

    def test_artifact_inspection_skips_unsafe_and_malformed_entries(self):
        external = self.project / 'outside'
        external.write_text('private evidence')
        for command, directory, extension in [('logs', 'logs', 'log'), ('report', 'reports', 'md')]:
            folder = self.project / '.muzzle' / directory
            safe_name = f'hello-10-{"a" * 32}.{extension}'
            (folder / safe_name).write_text('safe')
            (folder / f'hello-11-{"b" * 32}.{extension}').symlink_to(external)
            (folder / f'hello-12-{"c" * 32}.{extension}').mkdir()
            for timestamp in ['notanumber', '99999999999999999999999999999']:
                (folder / f'hello-{timestamp}-{"d" * 32}.{extension}').write_text('unknown')
            receipt = json.loads(self.run_cli(command, 'hello', '--json'))
            self.assertEqual([a['path'] for a in receipt['artifacts']], [str((folder / safe_name).relative_to(self.project))])
            all_receipt = json.loads(self.run_cli(command, '--json'))
            self.assertNotIn(str((folder / f'hello-11-{"b" * 32}.{extension}').relative_to(self.project)),
                             [a['path'] for a in all_receipt['artifacts']])
            self.assertEqual(external.read_text(), 'private evidence')

    def test_snapshot_preserves_newlines_in_script_path(self):
        nested = self.project / '.muzzle/workflows/nested\nspace'
        nested.mkdir()
        script = nested / 'probe\nname.sh'
        script.write_text("printf 'newline-ok\\n'\n")
        (self.project / '.muzzle/manifests/newline.json').write_text(json.dumps({
            'name': 'newline', 'script': 'workflows/nested\nspace/probe\nname.sh', 'runner': 'bash'}))
        result = json.loads(self.run_cli('run', 'newline', '--json'))
        self.assertEqual((self.project / result['log_path']).read_text(), 'newline-ok\n')
        self.assertEqual(list((self.project / '.muzzle/state/executions').iterdir()), [])

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

    def test_report_suffix_preserves_workflow_name(self):
        name = 'release.md.notes.md'
        (self.project / f'.muzzle/workflows/{name}.sh').write_text('echo report-ok\n')
        summary = json.loads(self.run_cli('run', name, '--json'))
        markdown = self.project / summary['report_path']
        report = markdown.with_suffix('.json')
        self.assertTrue(report.is_file(), list(report.parent.iterdir()))
        self.assertEqual(json.loads(report.read_text()), summary)
        self.assertIn(str(report.relative_to(self.project)), markdown.read_text())
        receipt = json.loads(self.run_cli('clean', '--workflow', name, '--json'))
        self.assertEqual(receipt['removed'], 3)
        self.assertEqual(list(report.parent.iterdir()), [])

    def test_log_capture_failure_is_not_success(self):
        script = self.project / '.muzzle/workflows/log-failure.sh'
        script.write_text('echo captured\ntouch workflow-ran\nexit "${1:-0}"\n')
        shim = self.project / 'shim'
        shim.mkdir()
        # Consume all input so the producer can succeed; fail only the sink.
        (shim / 'tee').write_text('#!/bin/bash\ncat >/dev/null\necho "sink failed" >&2\nexit 1\n')
        (shim / 'tee').chmod(0o755)
        env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'])
        for workflow_exit, expected in [(0, 74), (9, 9)]:
            with self.subTest(workflow_exit=workflow_exit):
                result = subprocess.run([str(ROOT / 'muzzle'), 'run', 'log-failure',
                                         str(workflow_exit), '--verbose', '--json'],
                                        cwd=self.project, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                summary = json.loads(result.stdout)
                self.assertEqual(summary['status'], 'failed')
                self.assertIn('log capture failed', summary['error_excerpt'])
        (self.project / 'workflow-ran').unlink()
        log_path = self.project / '.muzzle/logs/is-a-directory'
        log_path.mkdir()
        command = ['bash', str(ROOT / 'src/muzzle_exec.sh'), 'bash', str(script),
                   hashlib.sha256(script.read_bytes()).hexdigest(),
                   '.muzzle/state/executions/' + 'b' * 32, str(log_path), 'true', 'kujo', '--']
        result = subprocess.run(command, cwd=self.project, capture_output=True, text=True)
        self.assertEqual(result.returncode, 74, result.stderr)
        self.assertFalse((self.project / 'workflow-ran').exists())

    def test_retention_ranking_and_unrecognized_files(self):
        artifacts = []
        for workflow in ['job', 'job-other', 'release.md', 'déploy', 'job-\nodd']:
            for extension in ['log', 'md', 'json']:
                directory = 'logs' if extension == 'log' else 'reports'
                for index, timestamp in enumerate([9, 10, 10, 100, 100]):
                    path = self.project / f'.muzzle/{directory}/{workflow}-{timestamp}-{index:032x}.{extension}'
                    path.write_text('evidence')
                    artifacts.append((path, workflow, extension, timestamp))
        for keep in [0, 1, 3, 20]:
            for workflow_filter in ['', 'job', 'absent']:
                with self.subTest(keep=keep, workflow=workflow_filter):
                    args = ['clean', '--keep', str(keep), '--dry-run', '--json']
                    if workflow_filter:
                        args += ['--workflow', workflow_filter]
                    receipt = json.loads(self.run_cli(*args))
                    expected = []
                    for path, workflow, extension, timestamp in artifacts:
                        newer = sum((other_time, other.name) > (timestamp, path.name)
                                    for other, wf, ext, other_time in artifacts
                                    if wf == workflow and ext == extension)
                        if (not workflow_filter or workflow_filter == workflow) and newer >= keep:
                            expected.append(str(path.relative_to(self.project)))
                    self.assertEqual({a['path'] for a in receipt['artifacts']}, set(expected))
                    self.assertEqual([a['path'] for a in receipt['artifacts']], sorted(expected))
                    self.assertEqual(receipt['removed'], 0)
        # Keep ranks apply before age selection: a future artifact still protects
        # the newest slot, leaving every older artifact eligible for removal.
        future = self.project / ('.muzzle/logs/job-9223372036854775807-' + 'e' * 32 + '.log')
        future.write_text('future')
        aged = json.loads(self.run_cli('clean', '--workflow', 'job', '--keep', '1',
                                       '--older-than', '1', '--dry-run', '--json'))
        self.assertEqual(sum(a['extension'] == '.log' for a in aged['artifacts']), 5)
        self.assertNotIn(str(future.relative_to(self.project)), [a['path'] for a in aged['artifacts']])
        future.unlink()
        invalid = self.project / ('.muzzle/logs/job-100-' + 'z' * 32 + '.log')
        invalid.write_text('not a Muzzle artifact')
        overflow = self.project / ('.muzzle/logs/job-99999999999999999999-' + 'a' * 32 + '.log')
        overflow.write_text('not a timestamp')
        directory = self.project / ('.muzzle/logs/job-100-' + 'f' * 32 + '.log')
        directory.mkdir()
        receipt = json.loads(self.run_cli('clean', '--json'))
        self.assertEqual(receipt['removed'], len(artifacts))
        self.assertEqual(receipt['skipped_unrecognized'], 3)
        self.assertEqual(invalid.read_text(), 'not a Muzzle artifact')
        self.assertTrue(directory.is_dir())
        self.assertEqual(overflow.read_text(), 'not a timestamp')

    def test_helper_diagnostics_are_redacted_and_bounded(self):
        shim = self.project / 'shim'
        shim.mkdir()
        tool = shim / 'ln'
        tool.write_text('#!/bin/bash\ncat diagnostic >&2\nexit 77\n')
        tool.chmod(0o755)
        env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'])
        diagnostics = [
            'TOKEN=PRIVATE-BODY\nuseful helper failure\n',
            '-----BEGIN PRIVATE KEY-----PRIVATE-BODY-----END PRIVATE KEY-----\nuseful helper failure\n',
            '-----BEGIN PRIVATE KEY-----\n' + 'PRIVATE-BODY\n' * 80,
            'PRIVATE-BODY' * 10000,
        ]
        for diagnostic in diagnostics:
            with self.subTest(length=len(diagnostic)):
                (self.project / 'diagnostic').write_text(diagnostic)
                result = subprocess.run([str(ROOT / 'muzzle'), 'run', 'hello-bash', '--json'],
                                        cwd=self.project, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(result.stderr, '')
                excerpt = json.loads(result.stdout)['error_excerpt']
                self.assertNotIn('PRIVATE-BODY', excerpt)
                self.assertLess(len(excerpt), 4096)
                if len(diagnostic) > 4096:
                    self.assertIn('Oversized helper diagnostic omitted', excerpt)
                else:
                    self.assertIn('[REDACTED', excerpt)
                if 'useful helper failure' in diagnostic:
                    self.assertIn('useful helper failure', excerpt)

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
