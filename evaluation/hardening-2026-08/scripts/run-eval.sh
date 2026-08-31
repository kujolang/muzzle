#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 5 ]]; then
	printf 'Usage: %s <eval-repo> <kujo-bin> <kujo-modules> <evidence-dir> <output-dir>\n' "$0" >&2
	exit 2
fi

eval_repo="$(cd "$1" && pwd)"
kujo_bin="$2"
kujo_modules="$3"
evidence_dir="$(cd "$4" && pwd)"
output_arg="$5"
mkdir -p "$output_arg"
output_dir="$(cd "$output_arg" && pwd)"
evaluation_root="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
	if [[ -L "$evaluation_root/evidence" ]]; then
		unlink "$evaluation_root/evidence"
	fi
}
trap cleanup EXIT

ln -s "$evidence_dir" "$evaluation_root/evidence"
cd "$evaluation_root"
set +e
env KUJO_MODULE_PATH="$kujo_modules" "$kujo_bin" run "$eval_repo/main.kujo" -- run eval-suite.json --output-dir "$output_dir" --json --no-color > "$output_dir/console.txt"
eval_status=$?
set -e
printf '%s\n' "$eval_status" > "$output_dir/exit-code.txt"
exit "$eval_status"
