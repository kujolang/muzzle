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

cleanup_files() {
	rm -f "$help_stdout" "$help_stderr" "$version_stdout" "$version_stderr" "$run_stdout" "$run_stderr" "$run_json_stdout" "$run_json_stderr" "$fail_stdout" "$fail_stderr" "$inject_stdout" "$inject_stderr"
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

"$MUZZLE_BIN" init >/dev/null
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
if grep -q "Command must come before flags" "$help_stdout" || grep -q "Command must come before flags" "$version_stdout"; then
	echo "Unexpected flag-order preamble in help/version output." >&2
	exit 1
fi

echo "Muzzle wrapper regression checks passed."
