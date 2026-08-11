#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MUZZLE_BIN="${ROOT_DIR}/muzzle"

tmpdir="$(mktemp -d /tmp/muzzle_regression.XXXXXX)"

cd "$tmpdir"

help_stdout="$(mktemp)"
help_stderr="$(mktemp)"
version_stdout="$(mktemp)"
version_stderr="$(mktemp)"
run_stdout="$(mktemp)"
run_stderr="$(mktemp)"
run_json_stdout="$(mktemp)"
run_json_stderr="$(mktemp)"
fail_stdout="$(mktemp)"
fail_stderr="$(mktemp)"
inject_stdout="$(mktemp)"
inject_stderr="$(mktemp)"
alias_stdout="$(mktemp)"
alias_stderr="$(mktemp)"
escape_stdout="$(mktemp)"
escape_stderr="$(mktemp)"
runner_stdout="$(mktemp)"
runner_stderr="$(mktemp)"
missing_stdout="$(mktemp)"
missing_stderr="$(mktemp)"
timeout_stdout="$(mktemp)"
timeout_stderr="$(mktemp)"
no_newline_stdout="$(mktemp)"
no_newline_stderr="$(mktemp)"

cleanup_files() {
	rm -f "$help_stdout" "$help_stderr" "$version_stdout" "$version_stderr" "$run_stdout" "$run_stderr" "$run_json_stdout" "$run_json_stderr" "$fail_stdout" "$fail_stderr" "$inject_stdout" "$inject_stderr" "$alias_stdout" "$alias_stderr" "$escape_stdout" "$escape_stderr" "$runner_stdout" "$runner_stderr" "$missing_stdout" "$missing_stderr" "$timeout_stdout" "$timeout_stderr" "$no_newline_stdout" "$no_newline_stderr"
	rm -rf "$tmpdir"
}
trap cleanup_files EXIT

"$MUZZLE_BIN" --help >"$help_stdout" 2>"$help_stderr"
if [[ -s "$help_stderr" ]]; then
	echo "Expected --help to be quiet on stderr." >&2
	exit 1
fi
if ! grep -q "Usage:" "$help_stdout"; then
	echo "Expected --help output to include Usage." >&2
	exit 1
fi

"$MUZZLE_BIN" --version >"$version_stdout" 2>"$version_stderr"
if [[ -s "$version_stderr" ]]; then
	echo "Expected --version to be quiet on stderr." >&2
	exit 1
fi
if ! grep -q "Muzzle v" "$version_stdout"; then
	echo "Expected --version output to include the version banner." >&2
	exit 1
fi

mkdir partial-init
cd partial-init
mkdir -p .muzzle/workflows
printf 'print("custom hello")\n' > .muzzle/workflows/hello.kujo
"$MUZZLE_BIN" init >/dev/null
if [[ ! -f .muzzle/workflows/hello.kujo || ! -f .muzzle/manifests/hello.json || ! -d .muzzle/state/loops ]]; then
	echo "Expected init to repair an incomplete .muzzle directory." >&2
	exit 1
fi
if ! grep -q 'custom hello' .muzzle/workflows/hello.kujo; then
	echo "Expected init repair to preserve existing workflow files." >&2
	exit 1
fi
cd ..

"$MUZZLE_BIN" init >/dev/null

list_output="$($MUZZLE_BIN list)"
if ! grep -q "hello" <<<"$list_output"; then
	echo "Expected initialized hello workflow in list output." >&2
	exit 1
fi

info_output="$($MUZZLE_BIN info hello)"
if ! grep -q "Workflow:[[:space:]]*hello" <<<"$info_output"; then
	echo "Expected info output for initialized hello workflow." >&2
	exit 1
fi

dry_run_output="$($MUZZLE_BIN run hello --dry-run)"
if ! grep -q "\[DRY RUN\]" <<<"$dry_run_output"; then
	echo "Expected dry-run marker in output." >&2
	exit 1
fi
if find .muzzle/logs .muzzle/reports -type f 2>/dev/null | grep -q .; then
	echo "Expected dry run not to create logs or reports." >&2
	exit 1
fi

"$MUZZLE_BIN" run hello >"$run_stdout" 2>"$run_stderr"
if [[ -s "$run_stderr" ]]; then
	echo "Expected muzzle run hello to be quiet on stderr." >&2
	exit 1
fi
if ! grep -q "Status:[[:space:]]*success" "$run_stdout"; then
	echo "Expected muzzle run hello to succeed." >&2
	exit 1
fi

"$MUZZLE_BIN" run hello --json >"$run_json_stdout" 2>"$run_json_stderr"
if [[ -s "$run_json_stderr" ]]; then
	echo "Expected muzzle run hello --json to be quiet on stderr." >&2
	exit 1
fi
if ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"success"' "$run_json_stdout"; then
	echo "Expected muzzle run hello --json to emit a success JSON summary." >&2
	exit 1
fi
log_count="$(find .muzzle/logs -maxdepth 1 -type f -name 'hello-*.log' | wc -l | tr -d ' ')"
report_count="$(find .muzzle/reports -maxdepth 1 -type f -name 'hello-*.md' | wc -l | tr -d ' ')"
if [[ "$log_count" -lt 2 || "$report_count" -lt 2 ]]; then
	echo "Expected consecutive runs to create distinct log/report files." >&2
	exit 1
fi

cat > .muzzle/workflows/echoargs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1"
EOF

cat > .muzzle/workflows/echoargs-and.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1"
EOF

cat > .muzzle/workflows/echoargs-subshell.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1"
EOF

cat > .muzzle/manifests/echoargs.json <<'EOF'
{
  "name": "echoargs",
  "summary": "Regression workflow that prints the first argument literally.",
  "runner": "bash",
  "script": "workflows/echoargs.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

cat > .muzzle/manifests/echoargs-and.json <<'EOF'
{
  "name": "echoargs-and",
  "summary": "Regression workflow that prints the first argument literally.",
  "runner": "bash",
  "script": "workflows/echoargs-and.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

cat > .muzzle/manifests/echoargs-subshell.json <<'EOF'
{
  "name": "echoargs-subshell",
  "summary": "Regression workflow that prints the first argument literally.",
  "runner": "bash",
  "script": "workflows/echoargs-subshell.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

set +e
"$MUZZLE_BIN" run echoargs 'safe; echo INJECTED' >"$inject_stdout" 2>"$inject_stderr"
inject_code=$?
set -e
if [[ "$inject_code" -ne 0 ]]; then
	echo "Expected muzzle run echoargs with semicolon arg to succeed, got $inject_code." >&2
	exit 1
fi
if grep -q '^INJECTED$' .muzzle/logs/echoargs-*.log 2>/dev/null; then
	echo "Unexpected injected command execution in echoargs log." >&2
	exit 1
fi
if ! grep -q "safe; echo INJECTED" .muzzle/logs/echoargs-*.log 2>/dev/null; then
	echo "Expected literal semicolon argument in echoargs log." >&2
	exit 1
fi

set +e
"$MUZZLE_BIN" run echoargs-and 'safe && echo INJECTED' >"$inject_stdout" 2>"$inject_stderr"
inject_code=$?
set -e
if [[ "$inject_code" -ne 0 ]]; then
	echo "Expected muzzle run echoargs-and with && arg to succeed, got $inject_code." >&2
	exit 1
fi
if grep -q '^INJECTED$' .muzzle/logs/echoargs-and-*.log 2>/dev/null; then
	echo "Unexpected injected command execution in echoargs-and log." >&2
	exit 1
fi
if ! grep -q "safe && echo INJECTED" .muzzle/logs/echoargs-and-*.log 2>/dev/null; then
	echo "Expected literal && argument in echoargs-and log." >&2
	exit 1
fi

set +e
"$MUZZLE_BIN" run echoargs-subshell '$(echo INJECTED)' >"$inject_stdout" 2>"$inject_stderr"
inject_code=$?
set -e
if [[ "$inject_code" -ne 0 ]]; then
	echo "Expected muzzle run echoargs-subshell with subshell arg to succeed, got $inject_code." >&2
	exit 1
fi
if grep -q '^INJECTED$' .muzzle/logs/echoargs-subshell-*.log 2>/dev/null; then
	echo "Unexpected injected command execution in echoargs-subshell log." >&2
	exit 1
fi
if ! grep -Fq '$(echo INJECTED)' .muzzle/logs/echoargs-subshell-*.log 2>/dev/null; then
	echo "Expected literal subshell argument in echoargs-subshell log." >&2
	exit 1
fi

set +e
"$MUZZLE_BIN" run hello --runner ruby >"$runner_stdout" 2>"$runner_stderr"
runner_code=$?
set -e
if [[ "$runner_code" -ne 2 ]]; then
	echo "Expected unsupported runner to exit 2, got $runner_code." >&2
	exit 1
fi
if ! grep -q "Unsupported runner 'ruby'" "$runner_stdout"; then
	echo "Expected unsupported runner message on stdout." >&2
	exit 1
fi

cat > .muzzle/workflows/shared-implementation.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'alias target: %s\n' "${1:-missing}"
EOF

cat > .muzzle/manifests/alias-check.json <<'EOF'
{
  "name": "alias-check",
  "summary": "Regression workflow that points at a differently named script.",
  "runner": "bash",
  "script": "workflows/shared-implementation.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

"$MUZZLE_BIN" run alias-check ok >"$alias_stdout" 2>"$alias_stderr"
if [[ -s "$alias_stderr" ]]; then
	echo "Expected manifest alias workflow to be quiet on stderr." >&2
	exit 1
fi
if ! grep -q "alias target: ok" .muzzle/logs/alias-check-*.log 2>/dev/null; then
	echo "Expected manifest script mapping to execute shared implementation." >&2
	exit 1
fi

cat > .muzzle/workflows/manifest-missing.sh <<'EOF'
#!/usr/bin/env bash
echo "should not run"
EOF

cat > .muzzle/manifests/manifest-missing.json <<'EOF'
{
  "name": "manifest-missing",
  "summary": "Regression workflow with an explicit missing script path.",
  "runner": "bash",
  "script": "workflows/missing-implementation.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

if grep -q '^manifest-missing[[:space:]]' <<<"$($MUZZLE_BIN list)"; then
	echo "Expected list to omit a manifest whose configured script is missing." >&2
	exit 1
fi

set +e
"$MUZZLE_BIN" run manifest-missing >"$missing_stdout" 2>"$missing_stderr"
missing_code=$?
set -e
if [[ "$missing_code" -ne 1 ]]; then
	echo "Expected manifest with missing explicit script to exit 1, got $missing_code." >&2
	exit 1
fi
if grep -q "should not run" .muzzle/logs/manifest-missing-*.log 2>/dev/null; then
	echo "Unexpected fallback to same-name script when manifest script is missing." >&2
	exit 1
fi

cat > .muzzle/workflows/malformed-manifest.sh <<'EOF'
#!/usr/bin/env bash
echo "malformed manifest fallback"
EOF
printf '{invalid json\n' > .muzzle/manifests/malformed-manifest.json
if ! grep -q '^malformed-manifest[[:space:]]' <<<"$($MUZZLE_BIN list)"; then
	echo "Expected list to discover a script whose optional manifest is malformed." >&2
	exit 1
fi

cat > .muzzle/workflows/invalid-manifest-runner.sh <<'EOF'
#!/usr/bin/env bash
echo "should not run"
EOF
cat > .muzzle/manifests/invalid-manifest-runner.json <<'EOF'
{
  "name": "invalid-manifest-runner",
  "runner": "ruby",
  "script": "workflows/invalid-manifest-runner.sh"
}
EOF
set +e
invalid_manifest_runner_output="$($MUZZLE_BIN run invalid-manifest-runner 2>&1)"
invalid_manifest_runner_code=$?
set -e
if [[ "$invalid_manifest_runner_code" -ne 2 || "$invalid_manifest_runner_output" != *"Unsupported runner 'ruby'"* ]]; then
	echo "Expected an invalid manifest runner to fail explicitly with exit 2." >&2
	exit 1
fi

"$MUZZLE_BIN" run echoargs -- '--json' >"$inject_stdout" 2>"$inject_stderr"
if ! grep -Fq -- '--json' .muzzle/logs/echoargs-*.log 2>/dev/null; then
	echo "Expected literal leading-dash argument after -- delimiter." >&2
	exit 1
fi
if grep -q '"status"' "$inject_stdout"; then
	echo "Expected literal --json after delimiter not to enable Muzzle JSON mode." >&2
	exit 1
fi

cat > escaped.sh <<'EOF'
#!/usr/bin/env bash
echo "escaped"
EOF
ln -s ../../escaped.sh .muzzle/workflows/escape.sh
cat > .muzzle/manifests/escape.json <<'EOF'
{
  "name": "escape",
  "summary": "Regression workflow that must not follow symlinks outside workflows.",
  "runner": "bash",
  "script": "workflows/escape.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

set +e
"$MUZZLE_BIN" run escape >"$escape_stdout" 2>"$escape_stderr"
escape_code=$?
set -e
if [[ "$escape_code" -ne 1 ]]; then
	echo "Expected symlink escape workflow to exit 1, got $escape_code." >&2
	exit 1
fi
if ! grep -q "outside expected directory" "$escape_stdout"; then
	echo "Expected symlink escape refusal message." >&2
	exit 1
fi

cat > .muzzle/workflows/fail.kujo <<'EOF'
print("This workflow fails intentionally.")
exit(3)
EOF

cat > .muzzle/manifests/fail.json <<'EOF'
{
  "name": "fail",
  "summary": "Intentional failure for regression coverage.",
  "runner": "kujo",
  "script": "workflows/fail.kujo",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF

set +e
"$MUZZLE_BIN" run fail >"$fail_stdout" 2>"$fail_stderr"
fail_code=$?
set -e
if [[ "$fail_code" -ne 3 ]]; then
	echo "Expected muzzle run fail to exit 3, got $fail_code." >&2
	exit 1
fi

cat > .muzzle/workflows/secret-fail.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo 'TOKEN=do-not-expose-this-value'
exit 4
EOF

set +e
secret_output="$($MUZZLE_BIN run secret-fail 2>&1)"
secret_code=$?
set -e
if [[ "$secret_code" -ne 4 ]]; then
	echo "Expected secret-fail workflow to preserve exit 4, got $secret_code." >&2
	exit 1
fi
if grep -q 'do-not-expose-this-value' <<<"$secret_output"; then
	echo "Expected quiet failure output to redact the secret value." >&2
	exit 1
fi
if ! grep -q '\[REDACTED' <<<"$secret_output"; then
	echo "Expected quiet failure output to include a redaction marker." >&2
	exit 1
fi
if grep -q 'do-not-expose-this-value' .muzzle/reports/secret-fail-*.json; then
	echo "Expected JSON report error excerpt to redact the secret value." >&2
	exit 1
fi
if ! grep -q 'do-not-expose-this-value' .muzzle/logs/secret-fail-*.log; then
	echo "Expected full local log to retain the workflow output." >&2
	exit 1
fi

cat > .muzzle/workflows/multiline-secret-fail.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '-----BEGIN PRIVATE KEY-----'
for part in 1 2 3 4 5 6; do
  echo "PRIVATE-BODY-${part}"
done
printf '%s\n' '-----END PRIVATE KEY-----'
exit 4
EOF
set +e
multiline_secret_output="$($MUZZLE_BIN run multiline-secret-fail 2>&1)"
multiline_secret_code=$?
set -e
if [[ "$multiline_secret_code" -ne 4 ]]; then
	echo "Expected multiline-secret-fail workflow to preserve exit 4." >&2
	exit 1
fi
if grep -q 'PRIVATE-BODY' <<<"$multiline_secret_output"; then
	echo "Expected a truncated error excerpt not to leak the tail of a multiline secret." >&2
	exit 1
fi
if ! grep -q '\[REDACTED' <<<"$multiline_secret_output"; then
	echo "Expected multiline secret failure output to include a redaction marker." >&2
	exit 1
fi

cat > .muzzle/workflows/no-newline-fail.sh <<'EOF'
#!/usr/bin/env bash
printf 'final output without newline'
exit 7
EOF
set +e
"$MUZZLE_BIN" run no-newline-fail >"$no_newline_stdout" 2>"$no_newline_stderr"
no_newline_code=$?
set -e
if [[ "$no_newline_code" -ne 7 ]]; then
	echo "Expected no-newline workflow to preserve exit 7, got $no_newline_code." >&2
	exit 1
fi
if ! grep -q 'final output without newline' .muzzle/logs/no-newline-fail-*.log; then
	echo "Expected no-newline workflow output to be preserved in the log." >&2
	exit 1
fi

cat > .muzzle/workflows/timeout.sh <<'EOF'
#!/usr/bin/env bash
sleep 2
EOF
set +e
"$MUZZLE_BIN" run timeout --timeout 1000 >"$timeout_stdout" 2>"$timeout_stderr"
timeout_code=$?
set -e
if [[ "$timeout_code" -eq 0 ]]; then
	echo "Expected a timed-out workflow to fail." >&2
	exit 1
fi
if ! grep -q 'Status:[[:space:]]*failed' "$timeout_stdout"; then
	echo "Expected a timed-out workflow summary to report failure." >&2
	exit 1
fi

cat > .muzzle/workflows/prefix.sh <<'EOF'
#!/usr/bin/env bash
echo "prefix"
EOF
cat > .muzzle/workflows/prefix-long.sh <<'EOF'
#!/usr/bin/env bash
echo "prefix-long"
EOF
"$MUZZLE_BIN" run prefix >/dev/null
"$MUZZLE_BIN" run prefix-long >/dev/null
prefix_logs_output="$($MUZZLE_BIN logs prefix)"
prefix_reports_output="$($MUZZLE_BIN report prefix)"
if grep -q 'prefix-long-' <<<"$prefix_logs_output"; then
	echo "Expected logs filter to match the exact workflow name." >&2
	exit 1
fi
if grep -q 'prefix-long-' <<<"$prefix_reports_output"; then
	echo "Expected report filter to match the exact workflow name." >&2
	exit 1
fi

loop_start_output="$($MUZZLE_BIN loop start hello --limit 1)"
set +e
second_loop_output="$($MUZZLE_BIN loop start hello-bash --limit 1 2>&1)"
second_loop_code=$?
set -e
if [[ "$second_loop_code" -eq 0 || "$second_loop_output" != *"active loop"* ]]; then
	echo "Expected loop start to refuse a second active loop." >&2
	exit 1
fi
loop_next_output="$($MUZZLE_BIN loop next)"
$MUZZLE_BIN loop done --note "verified lifecycle" >/dev/null
loop_status_output="$($MUZZLE_BIN loop status)"
loop_complete_output="$($MUZZLE_BIN loop next)"
loop_summary_output="$($MUZZLE_BIN loop summary)"
if ! grep -q "Loop 1/1: hello" <<<"$loop_next_output" || ! grep -q "Progress:[[:space:]]*1/1" <<<"$loop_status_output"; then
	echo "Expected loop next/status to report the active iteration." >&2
	exit 1
fi
if ! grep -q "complete" <<<"$loop_complete_output" || ! grep -q "verified lifecycle" <<<"$loop_summary_output"; then
	echo "Expected loop completion and summary to preserve the recorded note." >&2
	exit 1
fi

logs_output="$($MUZZLE_BIN logs hello)"
reports_output="$($MUZZLE_BIN report hello)"
if ! grep -q "Log: .muzzle/logs/hello-" <<<"$logs_output" || ! grep -q "Report: .muzzle/reports/hello-" <<<"$reports_output"; then
	echo "Expected filtered log and report discovery output." >&2
	exit 1
fi

$MUZZLE_BIN clean >/dev/null
if find .muzzle/logs .muzzle/reports -type f 2>/dev/null | grep -q .; then
	echo "Expected clean to remove all logs and reports." >&2
	exit 1
fi

if grep -q "Command must come before flags" "$help_stdout" || grep -q "Command must come before flags" "$version_stdout"; then
	echo "Unexpected flag-order preamble in help/version output." >&2
	exit 1
fi

echo "Muzzle wrapper regression checks passed."
