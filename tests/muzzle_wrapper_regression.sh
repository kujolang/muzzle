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
invalid_option_stdout="$(mktemp)"
invalid_option_stderr="$(mktemp)"
loop_transition_stdout="$(mktemp)"
loop_transition_stderr="$(mktemp)"
symlink_stdout="$(mktemp)"
symlink_stderr="$(mktemp)"
outside_dir="$(mktemp -d /tmp/muzzle_regression_outside.XXXXXX)"

cleanup_files() {
	rm -f "$help_stdout" "$help_stderr" "$version_stdout" "$version_stderr" "$run_stdout" "$run_stderr" "$run_json_stdout" "$run_json_stderr" "$fail_stdout" "$fail_stderr" "$inject_stdout" "$inject_stderr" "$alias_stdout" "$alias_stderr" "$escape_stdout" "$escape_stderr" "$runner_stdout" "$runner_stderr" "$missing_stdout" "$missing_stderr" "$timeout_stdout" "$timeout_stderr" "$no_newline_stdout" "$no_newline_stderr" "$invalid_option_stdout" "$invalid_option_stderr" "$loop_transition_stdout" "$loop_transition_stderr" "$symlink_stdout" "$symlink_stderr"
	rm -rf "$tmpdir" "$outside_dir"
}
trap cleanup_files EXIT

portable_file_size() {
	if stat -f '%z' "$1" >/dev/null 2>&1; then
		stat -f '%z' "$1"
	else
		stat -c '%s' "$1"
	fi
}

portable_sha256() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		sha256sum "$1" | awk '{print $1}'
	fi
}

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

set +e
"$MUZZLE_BIN" run hello-bash --timeout nope >"$invalid_option_stdout" 2>"$invalid_option_stderr"
invalid_timeout_code=$?
set -e
if [[ "$invalid_timeout_code" -ne 2 ]]; then
	echo "Expected a non-integer timeout to exit 2, got $invalid_timeout_code." >&2
	exit 1
fi
if ! grep -q "Invalid timeout 'nope'" "$invalid_option_stdout" || grep -q 'Runtime Error' "$invalid_option_stderr"; then
	echo "Expected a controlled invalid-timeout error without a Kujo runtime failure." >&2
	exit 1
fi

set +e
"$MUZZLE_BIN" run hello-bash --runner >"$invalid_option_stdout" 2>"$invalid_option_stderr"
missing_runner_code=$?
set -e
if [[ "$missing_runner_code" -ne 2 ]]; then
	echo "Expected --runner without a value to exit 2, got $missing_runner_code." >&2
	exit 1
fi

set +e
"$MUZZLE_BIN" loop start hello --limit nope >"$invalid_option_stdout" 2>"$invalid_option_stderr"
invalid_limit_code=$?
set -e
if [[ "$invalid_limit_code" -ne 2 ]]; then
	echo "Expected a non-integer loop limit to exit 2, got $invalid_limit_code." >&2
	exit 1
fi
if ! grep -q "Invalid loop limit 'nope'" "$invalid_option_stdout" || grep -q 'Runtime Error' "$invalid_option_stderr"; then
	echo "Expected a controlled invalid-loop-limit error without a Kujo runtime failure." >&2
	exit 1
fi
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
if [[ "$list_output" != "$($MUZZLE_BIN list)" ]]; then
	echo "Expected workflow discovery output to have deterministic ordering." >&2
	exit 1
fi

info_output="$($MUZZLE_BIN info hello)"
if ! grep -q "Workflow:[[:space:]]*hello" <<<"$info_output"; then
	echo "Expected info output for initialized hello workflow." >&2
	exit 1
fi

set +e
invalid_info_output="$($MUZZLE_BIN info ../hello 2>&1)"
invalid_info_code=$?
set -e
if [[ "$invalid_info_code" -ne 1 || "$invalid_info_output" != *"Invalid workflow name"* || "$invalid_info_output" == *"Runtime Error"* ]]; then
	echo "Expected info to reject an invalid workflow name cleanly." >&2
	exit 1
fi

cat > .muzzle/workflows/invalid-safety.sh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > .muzzle/manifests/invalid-safety.json <<'EOF'
{
  "name": "invalid-safety",
  "runner": "bash",
  "script": "workflows/invalid-safety.sh",
  "safety": []
}
EOF
set +e
invalid_safety_output="$($MUZZLE_BIN info invalid-safety 2>&1)"
invalid_safety_code=$?
set -e
if [[ "$invalid_safety_code" -ne 2 || "$invalid_safety_output" != *"safety must be an object"* || "$invalid_safety_output" == *"Runtime Error"* ]]; then
	echo "Expected invalid manifest safety metadata to fail with a controlled error." >&2
	exit 1
fi
rm .muzzle/manifests/invalid-safety.json .muzzle/workflows/invalid-safety.sh

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

printf '[]\n' > .muzzle/state/session.json
set +e
malformed_session_output="$($MUZZLE_BIN run hello-bash 2>&1)"
malformed_session_code=$?
set -e
if [[ "$malformed_session_code" -ne 0 || "$malformed_session_output" == *"Runtime Error"* ]]; then
	echo "Expected an invalid session-state type not to override a successful workflow result." >&2
	exit 1
fi
printf '{bad\n' > .muzzle/state/session.json
set +e
malformed_session_output="$($MUZZLE_BIN run hello-bash 2>&1)"
malformed_session_code=$?
set -e
if [[ "$malformed_session_code" -ne 0 || "$malformed_session_output" == *"Runtime Error"* ]]; then
	echo "Expected malformed session JSON not to override a successful workflow result." >&2
	exit 1
fi
printf '{"total_runs":"invalid"}\n' > .muzzle/state/session.json
set +e
malformed_session_output="$($MUZZLE_BIN run hello-bash 2>&1)"
malformed_session_code=$?
set -e
if [[ "$malformed_session_code" -ne 0 || "$malformed_session_output" == *"Runtime Error"* ]]; then
	echo "Expected an invalid session counter not to override a successful workflow result." >&2
	exit 1
fi
printf '{"project":"","last_workflow":null,"last_run_at":null,"total_runs":0}\n' > .muzzle/state/session.json

for _run_idx in $(seq 1 12); do
	"$MUZZLE_BIN" run hello-bash >/dev/null &
done
wait
session_total_runs="$(grep -o '"total_runs":[0-9]*' .muzzle/state/session.json | cut -d: -f2)"
if [[ "$session_total_runs" -ne 12 ]]; then
	echo "Expected 12 concurrent successful runs to record total_runs=12, got ${session_total_runs:-missing}." >&2
	exit 1
fi
printf '{"project":"","last_workflow":null,"last_run_at":null,"total_runs":0}\n' > .muzzle/state/session.json

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

cat > .muzzle/manifests/invalid-args.json <<'EOF'
{
  "name": "invalid-args",
  "runner": "bash",
  "script": "workflows/shared-implementation.sh",
  "args": null
}
EOF
set +e
invalid_args_output="$($MUZZLE_BIN info invalid-args 2>&1)"
invalid_args_code=$?
set -e
if [[ "$invalid_args_code" -ne 2 || "$invalid_args_output" != *"MANIFEST_ARGS_TYPE"* || "$invalid_args_output" == *"Runtime Error"* ]]; then
	echo "Expected invalid manifest argument metadata to fail with a controlled error." >&2
	exit 1
fi
rm .muzzle/manifests/invalid-args.json
cat > .muzzle/manifests/unknown-field.json <<'EOF'
{"schema_version":"muzzle.manifest/v1","name":"unknown-field","script":"workflows/shared-implementation.sh","unexpected":true}
EOF
set +e
unknown_field_output="$($MUZZLE_BIN info unknown-field --json 2>&1)"
unknown_field_code=$?
set -e
if [[ "$unknown_field_code" -ne 2 || "$unknown_field_output" != *'"code":"MANIFEST_UNKNOWN_FIELD"'* ]]; then
	echo "Expected strict manifests to reject unknown fields." >&2
	exit 1
fi
rm .muzzle/manifests/unknown-field.json
if grep -q "should not run" .muzzle/logs/manifest-missing-*.log 2>/dev/null; then
	echo "Unexpected fallback to same-name script when manifest script is missing." >&2
	exit 1
fi
rm .muzzle/manifests/manifest-missing.json .muzzle/workflows/manifest-missing.sh

cat > .muzzle/workflows/malformed-manifest.sh <<'EOF'
#!/usr/bin/env bash
echo "malformed manifest fallback"
EOF
printf '{invalid json\n' > .muzzle/manifests/malformed-manifest.json
set +e
malformed_manifest_output="$($MUZZLE_BIN list 2>&1)"
malformed_manifest_code=$?
set -e
if [[ "$malformed_manifest_code" -ne 2 || "$malformed_manifest_output" != *"malformed JSON"* ]]; then
	echo "Expected list to distinguish and reject malformed manifest JSON." >&2
	exit 1
fi
rm .muzzle/manifests/malformed-manifest.json

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
if [[ "$invalid_manifest_runner_code" -ne 2 || "$invalid_manifest_runner_output" != *"runner must be one of"* ]]; then
	echo "Expected an invalid manifest runner to fail strict validation with exit 2." >&2
	exit 1
fi
rm .muzzle/manifests/invalid-manifest-runner.json

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
if ! grep -q "outside the expected directory" "$escape_stdout"; then
	echo "Expected symlink escape refusal message." >&2
	exit 1
fi
rm .muzzle/manifests/escape.json .muzzle/workflows/escape.sh

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
if grep -q 'do-not-expose-this-value' .muzzle/reports/secret-fail-*.md || ! grep -q '\[REDACTED' .muzzle/reports/secret-fail-*.md; then
	echo "Expected Markdown reports to include a redacted failure excerpt." >&2
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
if [[ "$timeout_code" -ne 124 ]]; then
	echo "Expected a timed-out workflow to use exit 124, got $timeout_code." >&2
	exit 1
fi

cat > .muzzle/workflows/large-output.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for idx in $(seq 1 30000); do
  printf 'large-output-%06d-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz\n' "$idx"
done
EOF
large_json="$($MUZZLE_BIN run large-output --json)"
large_log="$(grep -o '"log_path":"[^"]*"' <<<"$large_json" | cut -d'"' -f4)"
if [[ -z "$large_log" || ! -f "$large_log" || "$(portable_file_size "$large_log")" -lt 2000000 ]]; then
	echo "Expected large workflow output to be preserved completely in its spooled log." >&2
	exit 1
fi
if [[ "${#large_json}" -gt 4096 || "$(tail -1 "$large_log")" != large-output-030000-* ]]; then
	echo "Expected large-output JSON to stay bounded while the complete log remains available." >&2
	exit 1
fi

cat > .muzzle/workflows/policy-check.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'policy approved\n'
EOF
cat > .muzzle/manifests/policy-check.json <<'EOF'
{
  "schema_version": "muzzle.manifest/v1",
  "name": "policy-check",
  "runner": "bash",
  "script": "workflows/policy-check.sh",
  "args": [
    {"name": "environment", "required": true, "allowed_values": ["staging", "production"]},
    {"name": "token", "required": false, "sensitive": true}
  ],
  "allow_extra_args": false,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": true,
    "human_approval_recommended": true
  }
}
EOF
set +e
policy_denial="$($MUZZLE_BIN run policy-check staging --policy enforce --validate-args --json 2>&1)"
policy_denial_code=$?
set -e
if [[ "$policy_denial_code" -ne 3 || "$policy_denial" != *'"code":"POLICY_APPROVAL_REQUIRED"'* ]]; then
	echo "Expected enforce policy to return a machine-readable approval denial." >&2
	exit 1
fi
policy_success="$($MUZZLE_BIN run policy-check staging --policy enforce --approve --validate-args --json)"
if [[ "$policy_success" != *'"status":"success"'* ]]; then
	echo "Expected explicit policy approval to permit the workflow." >&2
	exit 1
fi
set +e
arg_denial="$($MUZZLE_BIN run policy-check invalid --approve --validate-args --json 2>&1)"
arg_denial_code=$?
set -e
if [[ "$arg_denial_code" -ne 2 || "$arg_denial" != *'"code":"ARG_VALUE_NOT_ALLOWED"'* ]]; then
	echo "Expected opt-in argument allowlist validation." >&2
	exit 1
fi
sensitive_preview="$($MUZZLE_BIN run policy-check staging super-secret --dry-run)"
if [[ "$sensitive_preview" == *'super-secret'* || "$sensitive_preview" != *'[REDACTED]'* ]]; then
	echo "Expected dry-run to redact manifest arguments marked sensitive." >&2
	exit 1
fi

if command -v openssl >/dev/null 2>&1; then
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out policy-private.pem >/dev/null 2>&1
	openssl pkey -in policy-private.pem -pubout -out policy-public.pem >/dev/null 2>&1
	printf '%s\n' '{"schema_version":"muzzle.policy/v1","workflows":["policy-check"],"approved":true,"issuer":"regression"}' > policy-bundle.json
	openssl dgst -sha256 -sign policy-private.pem -out policy-signature.bin policy-bundle.json
	signed_policy_output="$($MUZZLE_BIN run policy-check staging --policy-bundle policy-bundle.json --policy-public-key policy-public.pem --policy-signature policy-signature.bin --json)"
	if [[ "$signed_policy_output" != *'"status":"success"'* ]]; then
		echo "Expected a valid detached policy signature to authorize the workflow." >&2
		exit 1
	fi
	printf ' ' >> policy-bundle.json
	set +e
	signed_policy_denial="$($MUZZLE_BIN run policy-check staging --policy-bundle policy-bundle.json --policy-public-key policy-public.pem --policy-signature policy-signature.bin --json 2>&1)"
	signed_policy_denial_code=$?
	set -e
	if [[ "$signed_policy_denial_code" -ne 3 || "$signed_policy_denial" != *'"code":"POLICY_SIGNATURE_INVALID"'* ]]; then
		echo "Expected policy bundle tampering to fail closed." >&2
		exit 1
	fi
	rm policy-private.pem policy-public.pem policy-bundle.json policy-signature.bin
fi

script_digest="$(portable_sha256 .muzzle/workflows/policy-check.sh)"
sed "s/\"script\": \"workflows\/policy-check.sh\",/\"script\": \"workflows\/policy-check.sh\",\n  \"script_sha256\": \"${script_digest}\",/" .muzzle/manifests/policy-check.json > .muzzle/manifests/policy-check-pinned.json
mv .muzzle/manifests/policy-check-pinned.json .muzzle/manifests/policy-check.json
integrity_success="$($MUZZLE_BIN integrity policy-check --json)"
if [[ "$integrity_success" != *'"status":"INTEGRITY_VERIFIED"'* ]]; then
	echo "Expected integrity command to verify a pinned workflow checksum." >&2
	exit 1
fi
printf '# drift\n' >> .muzzle/workflows/policy-check.sh
set +e
integrity_denial="$($MUZZLE_BIN run policy-check staging --approve --json 2>&1)"
integrity_denial_code=$?
set -e
if [[ "$integrity_denial_code" -ne 3 || "$integrity_denial" != *'"code":"INTEGRITY_MISMATCH"'* ]]; then
	echo "Expected checksum drift to block workflow execution." >&2
	exit 1
fi

set +e
doctor_mismatch="$($MUZZLE_BIN doctor --json 2>&1)"
doctor_mismatch_code=$?
set -e
if [[ "$doctor_mismatch_code" -ne 1 || "$doctor_mismatch" != *'"code":"INTEGRITY_MISMATCH"'* ]]; then
	echo "Expected doctor to report checksum drift with a stable finding code." >&2
	exit 1
fi
rm .muzzle/manifests/policy-check.json .muzzle/workflows/policy-check.sh
set +e
doctor_ok_output="$($MUZZLE_BIN doctor --json 2>&1)"
doctor_ok_code=$?
set -e
if [[ "$doctor_ok_code" -ne 0 || "$doctor_ok_output" != *'"ok":true'* ]]; then
	echo "Expected doctor to pass after invalid fixtures are removed." >&2
	echo "$doctor_ok_output" >&2
	exit 1
fi

list_json_output="$($MUZZLE_BIN list --json)"
info_json_output="$($MUZZLE_BIN info hello --json)"
logs_json_output="$($MUZZLE_BIN logs --json)"
reports_json_output="$($MUZZLE_BIN report --json)"
if [[ "$list_json_output" != *'"schema_version":"muzzle.command/v1"'* || "$info_json_output" != *'"command":"info"'* || "$logs_json_output" != *'"command":"logs"'* || "$reports_json_output" != *'"command":"report"'* ]]; then
	echo "Expected inspection commands to emit parseable versioned JSON envelopes." >&2
	exit 1
fi

"$MUZZLE_BIN" run hello >/dev/null
sleep 0.02
"$MUZZLE_BIN" run hello >/dev/null
retention_preview="$($MUZZLE_BIN clean --workflow hello --keep 1 --dry-run --json)"
if [[ "$retention_preview" != *'"dry_run":true'* || "$retention_preview" == *'"selected":0'* ]]; then
	echo "Expected retention cleanup to preview older recognized artifacts." >&2
	exit 1
fi
"$MUZZLE_BIN" clean --workflow hello --keep 1 >/dev/null
retained_logs="$(find .muzzle/logs -maxdepth 1 -type f -name 'hello-*.log' | grep -c '/hello-[0-9]')"
retained_reports="$(find .muzzle/reports -maxdepth 1 -type f -name 'hello-*.md' | grep -c '/hello-[0-9]')"
if [[ "$retained_logs" -ne 1 || "$retained_reports" -ne 1 ]]; then
	echo "Expected retention cleanup to keep exactly one run per artifact type." >&2
	echo "Retained logs: $retained_logs; retained Markdown reports: $retained_reports" >&2
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
set +e
"$MUZZLE_BIN" loop done --note "premature" >"$loop_transition_stdout" 2>"$loop_transition_stderr"
premature_done_code=$?
set -e
if [[ "$premature_done_code" -ne 1 ]]; then
	echo "Expected loop done to reject completion before the first iteration starts." >&2
	exit 1
fi
loop_next_output="$($MUZZLE_BIN loop next)"
set +e
"$MUZZLE_BIN" loop next >"$loop_transition_stdout" 2>"$loop_transition_stderr"
repeated_next_code=$?
set -e
if [[ "$repeated_next_code" -ne 1 ]]; then
	echo "Expected loop next to reject advancing an unfinished iteration." >&2
	exit 1
fi
$MUZZLE_BIN loop done --note $'verified | lifecycle\ncontinued' >/dev/null
set +e
"$MUZZLE_BIN" loop done --note "duplicate" >"$loop_transition_stdout" 2>"$loop_transition_stderr"
duplicate_done_code=$?
set -e
if [[ "$duplicate_done_code" -ne 1 ]]; then
	echo "Expected loop done to reject a duplicate completion record." >&2
	exit 1
fi
loop_status_output="$($MUZZLE_BIN loop status)"
loop_complete_output="$($MUZZLE_BIN loop next)"
loop_summary_output="$($MUZZLE_BIN loop summary)"
if ! grep -q "Loop 1/1: hello" <<<"$loop_next_output" || ! grep -q "Progress:[[:space:]]*1/1" <<<"$loop_status_output"; then
	echo "Expected loop next/status to report the active iteration." >&2
	exit 1
fi
if ! grep -q "complete" <<<"$loop_complete_output" || ! grep -Fq 'verified \| lifecycle continued' <<<"$loop_summary_output"; then
	echo "Expected loop completion and summary to preserve the recorded note." >&2
	exit 1
fi
if [[ "$(grep -c '^| 1 | done |' <<<"$loop_summary_output")" -ne 1 ]]; then
	echo "Expected loop summary notes with pipes and newlines to remain one valid Markdown row." >&2
	exit 1
fi

logs_output="$($MUZZLE_BIN logs hello)"
reports_output="$($MUZZLE_BIN report hello)"
if ! grep -q "Log: .muzzle/logs/hello-" <<<"$logs_output" || ! grep -q "Report: .muzzle/reports/hello-" <<<"$reports_output"; then
	echo "Expected filtered log and report discovery output." >&2
	exit 1
fi

mkdir .muzzle/logs/undeletable-entry
set +e
"$MUZZLE_BIN" clean >"$invalid_option_stdout" 2>"$invalid_option_stderr"
clean_failure_code=$?
set -e
if [[ "$clean_failure_code" -ne 0 || ! -d .muzzle/logs/undeletable-entry ]]; then
	echo "Expected clean to preserve and report unrecognized artifact entries." >&2
	exit 1
fi
rmdir .muzzle/logs/undeletable-entry
$MUZZLE_BIN clean >/dev/null
if find .muzzle/logs .muzzle/reports -type f 2>/dev/null | grep -q .; then
	echo "Expected clean to remove all logs and reports." >&2
	exit 1
fi

mkdir symlink-project
cd symlink-project
"$MUZZLE_BIN" init >/dev/null
mkdir "$outside_dir/workflows" "$outside_dir/logs"
cp .muzzle/workflows/hello-bash.sh "$outside_dir/workflows/hello-bash.sh"
rm .muzzle/workflows/hello.kujo .muzzle/workflows/hello-bash.sh
rmdir .muzzle/workflows
ln -s "$outside_dir/workflows" .muzzle/workflows
set +e
"$MUZZLE_BIN" run hello-bash >"$symlink_stdout" 2>"$symlink_stderr"
symlink_workflow_code=$?
set -e
if [[ "$symlink_workflow_code" -ne 1 ]]; then
	echo "Expected a symlinked workflows root outside .muzzle to be rejected." >&2
	exit 1
fi

rm .muzzle/workflows
mkdir .muzzle/workflows
cp "$outside_dir/workflows/hello-bash.sh" .muzzle/workflows/hello-bash.sh
rmdir .muzzle/logs
ln -s "$outside_dir/logs" .muzzle/logs
set +e
"$MUZZLE_BIN" run hello-bash >"$symlink_stdout" 2>"$symlink_stderr"
symlink_log_code=$?
set -e
if [[ "$symlink_log_code" -ne 1 || -n "$(find "$outside_dir/logs" -maxdepth 1 -type f -print -quit)" ]]; then
	echo "Expected a symlinked log directory outside .muzzle to be rejected without external writes." >&2
	exit 1
fi
printf 'preserve me\n' > "$outside_dir/logs/sentinel.log"
set +e
"$MUZZLE_BIN" clean >"$symlink_stdout" 2>"$symlink_stderr"
symlink_clean_code=$?
set -e
if [[ "$symlink_clean_code" -ne 1 || ! -f "$outside_dir/logs/sentinel.log" ]]; then
	echo "Expected clean to reject an external symlink without deleting external files." >&2
	exit 1
fi
cd ..

mkdir malformed-loop-project
cd malformed-loop-project
"$MUZZLE_BIN" init >/dev/null
printf '{bad\n' > .muzzle/state/loops/corrupt.json
set +e
malformed_loop_output="$($MUZZLE_BIN loop status 2>&1)"
malformed_loop_code=$?
set -e
if [[ "$malformed_loop_code" -ne 1 || "$malformed_loop_output" != *"Invalid loop state"* || "$malformed_loop_output" == *"Runtime Error"* ]]; then
	echo "Expected malformed loop state to fail with a controlled, non-mutating error." >&2
	exit 1
fi
cd ..

mkdir invalid-directory-project
cd invalid-directory-project
printf 'not a directory\n' > .muzzle
set +e
invalid_directory_output="$($MUZZLE_BIN init 2>&1)"
invalid_directory_code=$?
set -e
if [[ "$invalid_directory_code" -ne 1 || "$invalid_directory_output" == *"Runtime Error"* ]]; then
	echo "Expected init to reject a non-directory .muzzle path with a controlled error." >&2
	exit 1
fi
rm .muzzle
"$MUZZLE_BIN" init >/dev/null
rmdir .muzzle/logs
printf 'not a directory\n' > .muzzle/logs
set +e
invalid_directory_output="$($MUZZLE_BIN run hello-bash 2>&1)"
invalid_directory_code=$?
set -e
if [[ "$invalid_directory_code" -ne 1 || "$invalid_directory_output" == *"Runtime Error"* ]]; then
	echo "Expected run to reject a non-directory artifact path with a controlled error." >&2
	exit 1
fi
cd ..

if grep -q "Command must come before flags" "$help_stdout" || grep -q "Command must come before flags" "$version_stdout"; then
	echo "Unexpected flag-order preamble in help/version output." >&2
	exit 1
fi

echo "Muzzle wrapper regression checks passed."
