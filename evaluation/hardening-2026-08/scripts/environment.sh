#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
	printf 'Usage: %s <kujo-bin> <kujo-modules> <output.txt>\n' "$0" >&2
	exit 2
fi

kujo_bin="$1"
kujo_modules="$2"
output="$3"
mkdir -p "$(dirname "$output")"
{
	printf 'captured_at_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
	printf 'os_product=%s\n' "$(sw_vers -productName)"
	printf 'os_version=%s\n' "$(sw_vers -productVersion)"
	printf 'os_build=%s\n' "$(sw_vers -buildVersion)"
	printf 'kernel=%s\n' "$(uname -srv)"
	printf 'architecture=%s\n' "$(uname -m)"
	printf 'cpu=%s\n' "$(sysctl -n machdep.cpu.brand_string)"
	printf 'physical_cores=%s\n' "$(sysctl -n hw.physicalcpu)"
	printf 'logical_cores=%s\n' "$(sysctl -n hw.logicalcpu)"
	printf 'ram_bytes=%s\n' "$(sysctl -n hw.memsize)"
	printf 'filesystem=%s\n' "$(diskutil info / | awk -F: '/File System Personality/ {gsub(/^[[:space:]]+/, "", $2); print $2}')"
	printf 'kujo=%s\n' "$(env KUJO_MODULE_PATH="$kujo_modules" "$kujo_bin" --version | head -1)"
	printf 'kujo_binary=%s\n' "$kujo_bin"
	printf 'kujo_binary_sha256=%s\n' "$(shasum -a 256 "$kujo_bin" | awk '{print $1}')"
	printf 'rust=%s\n' "$(rustc --version)"
	printf 'cargo=%s\n' "$(cargo --version)"
	printf 'bash=%s\n' "$(bash --version | head -1)"
	printf 'node=%s\n' "$(node --version)"
	printf 'python=%s\n' "$(python3 --version 2>&1)"
	printf 'openssl=%s\n' "$(openssl version)"
	printf 'timezone=%s\n' "$(date +%Z)"
	printf 'load_average=%s\n' "$(sysctl -n vm.loadavg)"
} > "$output"
