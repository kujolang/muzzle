#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install_root="$(mktemp -d /tmp/muzzle_install_regression.XXXXXX)"
symlink_root="$(mktemp -d /tmp/muzzle_install_symlink.XXXXXX)"

cleanup() {
	rm -rf "$install_root" "$symlink_root"
}
trap cleanup EXIT

preview="$(bash "$repo_root/scripts/install.sh" --prefix "$install_root" --dry-run)"
[[ "$preview" == *"lib/muzzle/1.1.0"* ]] || { echo "Expected install dry-run to show the versioned destination." >&2; exit 1; }

bash "$repo_root/scripts/install.sh" --prefix "$install_root" >/dev/null
[[ -L "$install_root/bin/muzzle" && -f "$install_root/lib/muzzle/1.1.0/muzzle.kujo" ]] || { echo "Expected versioned files and launcher symlink." >&2; exit 1; }

version_output="$(KUJO_BIN="${KUJO_BIN:-kujo}" "$install_root/bin/muzzle" --version)"
[[ "$version_output" == *"Muzzle v1.1.0"* ]] || { echo "Expected installed launcher to resolve its versioned runtime." >&2; exit 1; }

set +e
bash "$repo_root/scripts/install.sh" --prefix "$install_root" >/dev/null 2>&1
repeat_code=$?
set -e
[[ "$repeat_code" -eq 3 ]] || { echo "Expected installer to refuse replacement without --force." >&2; exit 1; }

mkdir -p "$symlink_root/prefix/lib/muzzle" "$symlink_root/outside"
ln -s "$symlink_root/outside" "$symlink_root/prefix/lib/muzzle/1.1.0"
set +e
bash "$repo_root/scripts/install.sh" --prefix "$symlink_root/prefix" --force >/dev/null 2>&1
symlink_code=$?
set -e
[[ "$symlink_code" -eq 3 ]] || { echo "Expected installer to reject a symlinked version root." >&2; exit 1; }
[[ -z "$(find "$symlink_root/outside" -mindepth 1 -print -quit)" ]] || { echo "Expected symlink rejection before external writes." >&2; exit 1; }

echo "Muzzle install regression checks passed."
