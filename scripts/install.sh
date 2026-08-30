#!/usr/bin/env bash
set -euo pipefail

VERSION="1.1.0"
PREFIX="${PREFIX:-/usr/local}"
DRY_RUN=0
FORCE=0

usage() {
	cat <<'EOF'
Usage: scripts/install.sh [--prefix <path>] [--dry-run] [--force]

Installs Muzzle into <prefix>/lib/muzzle/1.1.0 and creates
<prefix>/bin/muzzle. The default prefix is /usr/local.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--prefix)
			[[ $# -ge 2 ]] || { echo "Error: --prefix requires a path." >&2; exit 2; }
			PREFIX="$2"
			shift 2
			;;
		--dry-run) DRY_RUN=1; shift ;;
		--force) FORCE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Error: unknown option '$1'." >&2; usage >&2; exit 2 ;;
	esac
done

case "$PREFIX" in
	/*) ;;
	*) echo "Error: --prefix must be an absolute path." >&2; exit 2 ;;
esac

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_ROOT="${PREFIX%/}/lib/muzzle/${VERSION}"
BIN_DIR="${PREFIX%/}/bin"
LINK_PATH="${BIN_DIR}/muzzle"

for managed_path in "$INSTALL_ROOT" "$INSTALL_ROOT/src" "$INSTALL_ROOT/schemas" "$BIN_DIR"; do
	if [[ -L "$managed_path" ]]; then
		echo "Error: refusing symlinked installation path: ${managed_path}" >&2
		exit 3
	fi
done
if [[ -e "$INSTALL_ROOT" && ! -d "$INSTALL_ROOT" ]]; then
	echo "Error: installation root is not a directory: ${INSTALL_ROOT}" >&2
	exit 3
fi
if [[ -e "$BIN_DIR" && ! -d "$BIN_DIR" ]]; then
	echo "Error: binary path is not a directory: ${BIN_DIR}" >&2
	exit 3
fi

run() {
	if [[ "$DRY_RUN" -eq 1 ]]; then
		printf '+'
		printf ' %q' "$@"
		printf '\n'
		return 0
	fi
	"$@"
}

if [[ -e "$LINK_PATH" || -L "$LINK_PATH" ]]; then
	if [[ "$FORCE" -ne 1 ]]; then
		echo "Error: ${LINK_PATH} already exists; use --force to replace it." >&2
		exit 3
	fi
	run rm -f "$LINK_PATH"
fi
if [[ -e "$INSTALL_ROOT" && "$FORCE" -ne 1 ]]; then
	echo "Error: ${INSTALL_ROOT} already exists; use --force to replace its files." >&2
	exit 3
fi

run mkdir -p "$INSTALL_ROOT/src" "$INSTALL_ROOT/schemas" "$BIN_DIR"
run install -m 0755 "$SOURCE_ROOT/muzzle" "$INSTALL_ROOT/muzzle"
run install -m 0644 "$SOURCE_ROOT/muzzle.kujo" "$INSTALL_ROOT/muzzle.kujo"
for source_file in "$SOURCE_ROOT"/src/*.kujo; do
	run install -m 0644 "$source_file" "$INSTALL_ROOT/src/$(basename "$source_file")"
done
run install -m 0755 "$SOURCE_ROOT/src/muzzle_exec.sh" "$INSTALL_ROOT/src/muzzle_exec.sh"
for schema_file in "$SOURCE_ROOT"/schemas/*.json; do
	run install -m 0644 "$schema_file" "$INSTALL_ROOT/schemas/$(basename "$schema_file")"
done
run ln -s "$INSTALL_ROOT/muzzle" "$LINK_PATH"

echo "Installed Muzzle ${VERSION} at ${INSTALL_ROOT}"
echo "Launcher: ${LINK_PATH}"
