#!/usr/bin/env bash
set -euo pipefail

if [[ -f package.json ]]; then
	echo "Build system: npm"
	npm run build --if-present
elif [[ -f Cargo.toml ]]; then
	echo "Build system: Cargo"
	cargo check
elif [[ -f Makefile ]]; then
	echo "Build system: Make"
	make
else
	echo "No supported build entrypoint found; nothing to run."
fi
