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

echo "Muzzle process lifecycle regression checks passed."
