#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
muzzle_bin="${root_dir}/muzzle"
test_dir="$(mktemp -d /tmp/muzzle_process_regression.XXXXXX)"

cleanup() {
	rm -rf "$test_dir"
}
trap cleanup EXIT

cd "$test_dir"
"$muzzle_bin" init >/dev/null
cat > .muzzle/workflows/race-helper.sh <<'EOF'
printf 'relative-helper-ok\n'
EOF
cat > .muzzle/workflows/snapshot-denial.sh <<'EOF'
#!/usr/bin/env bash
printf 'validated-original\n'
EOF
MUZZLE_TEST_MODE=1 MUZZLE_TEST_PAUSE_BEFORE_SNAPSHOT_MS=1000 \
	"$muzzle_bin" run snapshot-denial --timeout 10000 >/dev/null 2>&1 &
denial_run_pid=$!
denial_owner=""
for _wait_idx in $(seq 1 100); do
	denial_owner="$(find .muzzle/state/executions -name .owner -type f -print -quit 2>/dev/null || true)"
	[[ -n "$denial_owner" ]] && break
	sleep 0.05
done
if [[ -z "$denial_owner" ]]; then
	echo "Expected pre-snapshot execution state to become ready." >&2
	exit 1
fi
cat > .muzzle/workflows/snapshot-denial.sh <<'EOF'
#!/usr/bin/env bash
printf 'mutated-before-snapshot\n'
EOF
set +e
wait "$denial_run_pid"
denial_code=$?
set -e
denial_log="$(ls -t .muzzle/logs/snapshot-denial-*.log | head -1)"
if [[ "$denial_code" -ne 3 ]] || ! grep -q 'workflow changed after validation; execution denied' "$denial_log" || grep -q 'mutated-before-snapshot' "$denial_log"; then
	echo "Expected a pre-snapshot workflow mutation to fail closed with exit 3." >&2
	exit 1
fi

cat > .muzzle/workflows/snapshot-race.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'trusted-snapshot\n'
printf 'script-identity=%s\n' "$0"
source "$(dirname "${BASH_SOURCE[0]}")/race-helper.sh"
EOF

MUZZLE_TEST_MODE=1 MUZZLE_TEST_PAUSE_AFTER_SNAPSHOT_MS=1000 \
	"$muzzle_bin" run snapshot-race --timeout 10000 >/dev/null 2>&1 &
race_run_pid=$!
snapshot_ready=""
for _wait_idx in $(seq 1 100); do
	snapshot_ready="$(find .muzzle/state/executions -name .snapshot-ready -type f -print -quit 2>/dev/null || true)"
	[[ -n "$snapshot_ready" ]] && break
	sleep 0.05
done
if [[ -z "$snapshot_ready" ]]; then
	echo "Expected the workflow snapshot to become ready." >&2
	exit 1
fi
cat > .muzzle/workflows/snapshot-race.sh <<'EOF'
#!/usr/bin/env bash
printf 'mutated-original\n'
EOF
set +e
wait "$race_run_pid"
race_code=$?
set -e
race_log="$(ls -t .muzzle/logs/snapshot-race-*.log | head -1)"
if [[ "$race_code" -ne 0 ]] || ! grep -q '^trusted-snapshot$' "$race_log" || grep -q 'mutated-original' "$race_log"; then
	echo "Expected execution to remain bound to the validated workflow bytes." >&2
	exit 1
fi
if ! grep -q '^script-identity=.muzzle/workflows/snapshot-race.sh$' "$race_log" || ! grep -q '^relative-helper-ok$' "$race_log"; then
	echo "Expected snapshot execution to preserve Bash script identity and relative helper loading." >&2
	exit 1
fi
if find .muzzle/state/executions -mindepth 1 -print -quit | grep -q .; then
	echo "Expected private execution snapshots to be removed after completion." >&2
	exit 1
fi

cat > .muzzle/workflows/process-tree.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 30 &
child_pid=$!
printf '%s\n' "$child_pid" > descendant.pid
wait "$child_pid"
EOF

set +e
"$muzzle_bin" run process-tree --timeout 1000 >/dev/null 2>&1
timeout_code=$?
set -e
descendant_pid="$(cat descendant.pid)"
if [[ "$timeout_code" -ne 124 ]] || kill -0 "$descendant_pid" 2>/dev/null; then
	echo "Expected timeout to return 124 and terminate the workflow process tree." >&2
	exit 1
fi
timeout_report="$(ls -t .muzzle/reports/process-tree-*.json | head -1)"
if ! grep -q '"timed_out":true' "$timeout_report"; then
	echo "Expected timeout to write a valid report with timed_out=true." >&2
	exit 1
fi

rm -f descendant.pid cancel.requested
set +e
"$muzzle_bin" run process-tree --timeout 30000 --cancel-file cancel.requested >/dev/null 2>&1 &
cancel_run_pid=$!
for _wait_idx in $(seq 1 50); do
	[[ -f descendant.pid ]] && break
	sleep 0.05
done
touch cancel.requested
wait "$cancel_run_pid"
cancel_code=$?
set -e
cancel_descendant_pid="$(cat descendant.pid)"
if [[ "$cancel_code" -ne 130 ]] || kill -0 "$cancel_descendant_pid" 2>/dev/null; then
	echo "Expected cancellation to return 130 and terminate the workflow process tree." >&2
	exit 1
fi
cancel_report="$(ls -t .muzzle/reports/process-tree-*.json | head -1)"
if ! grep -q '"cancelled":true' "$cancel_report"; then
	echo "Expected cancellation to write a valid report with cancelled=true." >&2
	exit 1
fi

rm -f descendant.pid cancel.requested
set +e
"$muzzle_bin" run process-tree --timeout 30000 >/dev/null 2>&1 &
interrupt_run_pid=$!
for _wait_idx in $(seq 1 50); do
	[[ -f descendant.pid ]] && break
	sleep 0.05
done
kill -TERM "$interrupt_run_pid"
wait "$interrupt_run_pid"
interrupt_code=$?
set -e
interrupt_descendant_pid="$(cat descendant.pid)"
if [[ "$interrupt_code" -ne 130 ]] || kill -0 "$interrupt_descendant_pid" 2>/dev/null; then
	echo "Expected an external termination signal to return 130 and terminate the workflow process tree." >&2
	echo "Interrupt exit: $interrupt_code; descendant: $interrupt_descendant_pid" >&2
	exit 1
fi
interrupt_report="$(ls -t .muzzle/reports/process-tree-*.json | head -1)"
if ! grep -q '"cancelled":true' "$interrupt_report"; then
	echo "Expected forwarded termination to write a valid cancellation report." >&2
	exit 1
fi
if find .muzzle/state/executions -mindepth 1 -print -quit | grep -q .; then
	echo "Expected private execution snapshots to be removed after timeout, cancellation, and interruption." >&2
	exit 1
fi

echo "Muzzle process lifecycle regression checks passed."
