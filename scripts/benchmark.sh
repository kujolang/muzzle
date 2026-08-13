#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
muzzle_bin="${repo_root}/muzzle"
iterations="${MUZZLE_BENCH_ITERATIONS:-5}"
line_count="${MUZZLE_BENCH_LINES:-50000}"
bench_dir="$(mktemp -d /tmp/muzzle_benchmark.XXXXXX)"

cleanup() {
	rm -rf "$bench_dir"
}
trap cleanup EXIT

file_size() {
	if stat -f '%z' "$1" >/dev/null 2>&1; then
		stat -f '%z' "$1"
	else
		stat -c '%s' "$1"
	fi
}

cd "$bench_dir"
"$muzzle_bin" init >/dev/null
cat > .muzzle/workflows/benchmark-output.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
for idx in \$(seq 1 ${line_count}); do
  printf 'benchmark-output-%08d-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz\\n' "\$idx"
done
EOF

timing_file="${bench_dir}/time.txt"
summary_file="${bench_dir}/summary.json"
if [[ "$(uname -s)" == "Darwin" ]]; then
	/usr/bin/time -l "$muzzle_bin" run benchmark-output --json >"$summary_file" 2>"$timing_file"
	peak_rss_bytes="$(awk '/maximum resident set size/ {print $1}' "$timing_file")"
else
	/usr/bin/time -v "$muzzle_bin" run benchmark-output --json >"$summary_file" 2>"$timing_file"
	peak_rss_kb="$(awk -F: '/Maximum resident set size/ {gsub(/ /, "", $2); print $2}' "$timing_file")"
	peak_rss_bytes="$((peak_rss_kb * 1024))"
fi

log_path="$(grep -o '"log_path":"[^"]*"' "$summary_file" | cut -d'"' -f4)"
log_bytes="$(file_size "$log_path")"
summary_bytes="$(file_size "$summary_file")"

startup_total_ms=0
for _idx in $(seq 1 "$iterations"); do
	start_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time()*1000')"
	"$muzzle_bin" --version >/dev/null
	end_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time()*1000')"
	startup_total_ms="$((startup_total_ms + end_ms - start_ms))"
done
startup_average_ms="$((startup_total_ms / iterations))"

concurrent_start_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time()*1000')"
for _idx in $(seq 1 "$iterations"); do
	"$muzzle_bin" run hello-bash >/dev/null &
done
wait
concurrent_end_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time()*1000')"

cat <<EOF
Muzzle local benchmark signal
  Platform:                $(uname -s) $(uname -m)
  Kujo:                    $(${KUJO_BIN:-kujo} --version | head -1)
  Startup average:         ${startup_average_ms}ms (${iterations} runs)
  Large-output lines:      ${line_count}
  Full log bytes:          ${log_bytes}
  JSON summary bytes:      ${summary_bytes}
  Peak RSS bytes:          ${peak_rss_bytes:-unknown}
  Concurrent runs:         ${iterations} in $((concurrent_end_ms - concurrent_start_ms))ms

This is a local regression signal, not a portable performance guarantee.
EOF
