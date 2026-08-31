#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 6 ]]; then
	printf 'Usage: %s <baseline> <current> <kujo-bin> <kujo-modules> <output-dir> <openssl>\n' "$0" >&2
	exit 2
fi

baseline_root="$1"
current_root="$2"
kujo_bin="$3"
kujo_modules="$4"
output_arg="$5"
mkdir -p "$(dirname "$output_arg")"
output_dir="$(cd "$(dirname "$output_arg")" && pwd)/$(basename "$output_arg")"
real_openssl="$6"
work_root="$(mktemp -d /tmp/muzzle-capability-eval.XXXXXX)"

cleanup() {
	rm -rf "$work_root"
}
trap cleanup EXIT

portable_mode() {
	if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}

run_one() {
	local label="$1"
	local root="$2"
	local project="$work_root/$label"
	local result_dir="$output_dir/$label"
	mkdir -p "$project" "$result_dir"
	cd "$project"
	env KUJO_BIN="$kujo_bin" KUJO_MODULE_PATH="$kujo_modules" "$root/muzzle" init >/dev/null

	env KUJO_BIN="$kujo_bin" KUJO_MODULE_PATH="$kujo_modules" "$root/muzzle" run hello-bash --json > "$result_dir/run.json"
	log_path="$(sed -n 's/.*"log_path":"\([^"]*\)".*/\1/p' "$result_dir/run.json")"
	report_path="$(sed -n 's/.*"report_path":"\([^"]*\)".*/\1/p' "$result_dir/run.json")"
	{
		printf 'log=%s\n' "$(portable_mode "$log_path")"
		printf 'markdown=%s\n' "$(portable_mode "$report_path")"
		printf 'json=%s\n' "$(portable_mode "${report_path%.md}.json")"
	} > "$result_dir/artifact-modes.txt"

	install_prefix="$work_root/${label}-install"
	external_target="$work_root/${label}-external"
	mkdir -p "$install_prefix/lib/muzzle" "$external_target" "$install_prefix/bin"
	ln -s "$external_target" "$install_prefix/lib/muzzle/$([[ "$label" == current ]] && printf '1.1.0' || printf '1.0.0')"
	set +e
	bash "$root/scripts/install.sh" --prefix "$install_prefix" --force >"$result_dir/install.stdout" 2>"$result_dir/install.stderr"
	install_exit=$?
	set -e
	printf '%s\n' "$install_exit" > "$result_dir/install.exit"
	find "$external_target" -type f -print | sort > "$result_dir/install-external-files.txt"

	instrument_root="$work_root/${label}-instrument"
	mkdir -p "$instrument_root"
	cp -R "$root/." "$instrument_root/"
	cp "$instrument_root/src/muzzle_exec.sh" "$instrument_root/src/real-muzzle-exec.sh"
	cat > "$instrument_root/src/muzzle_exec.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --cleanup* ]]; then
	exec bash "${REAL_HELPER}" "$@"
fi
: > "${RACE_MARKER}"
while [[ ! -f "${RACE_RELEASE}" ]]; do sleep 0.01; done
exec bash "${REAL_HELPER}" "$@"
WRAPPER
	chmod +x "$instrument_root/src/muzzle_exec.sh"
	cat > .muzzle/workflows/race.sh <<'SAFE'
#!/usr/bin/env bash
printf 'validated-bytes\n'
SAFE
	race_marker="$work_root/${label}.helper-entered"
	race_release="$work_root/${label}.helper-release"
	set +e
	env KUJO_BIN="$kujo_bin" KUJO_MODULE_PATH="$kujo_modules" REAL_HELPER="$instrument_root/src/real-muzzle-exec.sh" RACE_MARKER="$race_marker" RACE_RELEASE="$race_release" "$instrument_root/muzzle" run race --json >"$result_dir/race.json" 2>"$result_dir/race.stderr" &
	race_pid=$!
	set -e
	for _attempt in $(seq 1 500); do [[ -f "$race_marker" ]] && break; sleep 0.01; done
	cat > .muzzle/workflows/race.sh <<'MUTATED'
#!/usr/bin/env bash
printf 'mutated-bytes\n'
MUTATED
	: > "$race_release"
	set +e
	wait "$race_pid"
	race_exit=$?
	set -e
	printf '%s\n' "$race_exit" > "$result_dir/race.exit"
	race_log="$(sed -n 's/.*"log_path":"\([^"]*\)".*/\1/p' "$result_dir/race.json")"
	if [[ -n "$race_log" && -f "$race_log" ]]; then cp "$race_log" "$result_dir/race.log"; else : > "$result_dir/race.log"; fi

	mkdir -p "$work_root/${label}-bin"
	cat > "$work_root/${label}-bin/openssl" <<'OPENSSL_WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
"${REAL_OPENSSL}" "$@"
status=$?
if [[ "$status" -eq 0 ]]; then cp "${MALICIOUS_BUNDLE}" "${BUNDLE_SOURCE}"; fi
exit "$status"
OPENSSL_WRAPPER
	chmod +x "$work_root/${label}-bin/openssl"
	cat > safe-policy.json <<'SAFE_POLICY'
{"schema_version":"muzzle.policy/v1","workflows":["not-hello-bash"],"approved":true}
SAFE_POLICY
	cat > malicious-policy.json <<'MALICIOUS_POLICY'
{"schema_version":"muzzle.policy/v1","workflows":["hello-bash"],"approved":true}
MALICIOUS_POLICY
	"$real_openssl" genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out policy-private.pem >/dev/null 2>&1
	"$real_openssl" pkey -in policy-private.pem -pubout -out policy-public.pem >/dev/null 2>&1
	"$real_openssl" dgst -sha256 -sign policy-private.pem -out policy.sig safe-policy.json
	set +e
	env PATH="$work_root/${label}-bin:$PATH" REAL_OPENSSL="$real_openssl" BUNDLE_SOURCE="$project/safe-policy.json" MALICIOUS_BUNDLE="$project/malicious-policy.json" KUJO_BIN="$kujo_bin" KUJO_MODULE_PATH="$kujo_modules" "$root/muzzle" run hello-bash --json --policy-bundle safe-policy.json --policy-public-key policy-public.pem --policy-signature policy.sig >"$result_dir/policy.json" 2>"$result_dir/policy.stderr"
	policy_exit=$?
	set -e
	printf '%s\n' "$policy_exit" > "$result_dir/policy.exit"
}

mkdir -p "$output_dir"
run_one baseline "$baseline_root"
run_one current "$current_root"
