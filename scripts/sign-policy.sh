#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  scripts/sign-policy.sh sign <bundle.json> <private-key.pem> <signature.bin>
  scripts/sign-policy.sh verify <bundle.json> <public-key.pem> <signature.bin>

Uses an OpenSSL SHA-256 detached signature. Key generation and custody remain
the team's responsibility.
EOF
}

[[ $# -eq 4 ]] || { usage >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "Error: openssl is required." >&2; exit 1; }

case "$1" in
	sign) openssl dgst -sha256 -sign "$3" -out "$4" "$2" ;;
	verify) openssl dgst -sha256 -verify "$3" -signature "$4" "$2" ;;
	*) usage >&2; exit 2 ;;
esac
