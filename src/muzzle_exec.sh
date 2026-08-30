#!/usr/bin/env bash
set -u

if [[ "$#" -lt 6 ]]; then
	echo "muzzle-exec: expected runner, script, log, verbose flag, Kujo binary, and delimiter" >&2
	exit 2
fi

runner="$1"
script_path="$2"
log_path="$3"
verbose="$4"
kujo_bin="$5"
shift 5

if [[ "${1:-}" != "--" ]]; then
	echo "muzzle-exec: missing argument delimiter" >&2
	exit 2
fi
shift

# Create the Muzzle-owned log privately before the workflow starts, then restore
# the caller's umask so workflow-created files keep their original semantics.
caller_umask="$(umask)"
umask 077
: >"$log_path"
umask "$caller_umask"

case "$runner" in
	kujo)
		command_argv=("$kujo_bin" run "$script_path")
		;;
	bash)
		command_argv=(bash "$script_path")
		;;
	python)
		command_argv=(python3 "$script_path")
		;;
	node)
		command_argv=(node "$script_path")
		;;
	*)
		echo "muzzle-exec: unsupported runner: $runner" >&2
		exit 2
		;;
esac

if [[ "$verbose" == "true" ]]; then
	set +e
	"${command_argv[@]}" "$@" 2>&1 | tee "$log_path"
	workflow_status="${PIPESTATUS[0]}"
	set -e
else
	set +e
	"${command_argv[@]}" "$@" >"$log_path" 2>&1
	workflow_status="$?"
	set -e
fi

exit "$workflow_status"
