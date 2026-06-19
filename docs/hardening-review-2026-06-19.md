# Muzzle Hardening Review - 2026-06-19

## What Changed In This Pass

- Confirmed the root layout is intentional: `muzzle` is the Bash launcher, `muzzle.kujo` is the Kujo entrypoint, and reusable implementation lives in `src/`.
- Honored manifest `script` mappings during `run`, `info`, and loop start checks, including aliases where the workflow name differs from the script filename.
- Made explicit manifest `script` paths authoritative, so a missing or invalid declared script does not silently fall back to a same-named workflow file.
- Hardened script confinement with canonical path checks so symlinks that resolve outside `.muzzle/workflows/` are refused.
- Added literal workflow arg support with `--`, so workflows can receive values such as `--fix` without Muzzle treating them as its own flags.
- Added unsupported runner validation instead of silently falling back when a `--runner` value is misspelled.
- Made single-line secret redaction case-insensitive.
- Filtered debug-only Kujo compiler optimizer stats in the wrapper while preserving real stderr diagnostics.
- Expanded `tests/muzzle_wrapper_regression.sh` for manifest aliases, literal leading-dash args, symlink escape refusal, and invalid runner errors.
- Updated README and docs to present Muzzle as trusted-local production useful, not an untrusted-code sandbox or frozen enterprise API.

## Next Session Candidates

1. Add a dedicated Kujo unit-style test file for pure helpers in `src/workflow.kujo`, `src/runner.kujo`, and `src/redact.kujo` so regressions do not rely only on shell-level integration checks.
2. Add manifest validation warnings to `muzzle list` / `muzzle info` for missing scripts, unsupported runner values, malformed `args`, and missing safety metadata.
3. Add `muzzle doctor` to verify Kujo runtime identity, wrapper path, `.muzzle/` structure, log/report writability, and common misconfigurations.
4. Add `--since`, `--latest`, or count limiting to `muzzle logs` and `muzzle report` so large artifact directories stay easy to scan.
5. Add optional retention policy support for logs/reports, such as `muzzle clean --older-than 7d` or `--keep-last 20`.
6. Add checksum metadata for workflow scripts in manifests, then report drift in `muzzle info` before any future enforcement mode.
7. Add JSON schema documentation for workflow manifests and run reports, then pin it with regression fixtures.
8. Explore a non-shell execution path for Bash/Python/Node runners if Kujo adds process APIs that accept argv arrays directly.
9. Add Windows/path portability review once the Kujo runtime and launcher story is ready beyond Bash-first environments.
10. Build a polished example workflow pack that demonstrates Muzzle as a Kujo showcase: build, test, release-check, security-scan, and agent-loop flows with compact outputs.
