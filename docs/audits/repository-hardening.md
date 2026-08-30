# Repository Hardening Audit

## Repository

- Name: Muzzle
- Branch: `main`
- Starting SHA: `75c2e1d20ed060b22df01c44d28221cd672a02fa`
- Ending implementation SHA: `1de8e9a2b2847ca00e7ae5d7297842c8fadc3af2`
- Purpose: trusted-local Kujo CLI that runs project workflows while preserving full evidence and emitting compact agent-facing receipts.
- Important dependencies and integrations: Kujo runtime, Bash, optional Python/Node runners, OpenSSL for signed policy bundles, Git for enforce-mode checks, and Kujo ecosystem consumers using the CLI and JSON contracts.
- Broad-search exclusions: `.dogfood/`, `.muzzle/`, and `.kujo_cache/` were excluded as historical or generated output per repository policy.

## Baseline

The repository began clean on `main`. `make quality` passed before changes, including Kujo checks, shell syntax, whitespace checks, wrapper regressions, process lifecycle regressions, and installer regressions. Help, version, and workflow discovery passed.

The baseline benchmark on Darwin x86_64 with Kujo 1.0.0, five startup/concurrency iterations, and 50,000 output lines reported:

| Signal | Baseline |
| -- | --: |
| Startup average | 426 ms |
| Full log size | 4,000,000 bytes |
| JSON summary size | 482 bytes |
| Peak RSS | 34,648,064 bytes |
| Five concurrent runs | 2,614 ms |

An explicit artifact check under the host's `022` umask found workflow logs and both report formats created with mode `0644`. A representative successful JSON result was 463 bytes and had no schema discriminator.

## Findings

| ID | Priority | Area | Finding | Evidence | Action | Status |
| -- | -- | -- | -- | -- | -- | -- |
| MZ-HARD-001 | P1 | Security | Raw logs and reports can contain secrets but inherited a permissive host umask. | Baseline artifacts were mode `0644`; documentation confirms raw logs are unredacted. | Create logs and reports as owner-only `0600` files without changing workflow-created file semantics; add a cross-platform mode regression. | Fixed |
| MZ-HARD-002 | P0 | Security | Signed policy verification checked one pathname read, then parsed a second read, allowing a local replacement race to authorize unverified bytes. | `src/policy.kujo` passed the source path to OpenSSL and later reopened it. | Read once, create an owner-only immutable snapshot, verify the snapshot, and parse the same in-memory bytes. | Fixed |
| MZ-HARD-003 | P1 | Security/runtime | Script path and checksum validation are not bound to the file object later opened by the selected interpreter. | Path canonicalization and hashing precede a later pathname-based interpreter open. | Preserve behavior locally; request a Kujo runtime primitive for descriptor- or immutable-snapshot execution before changing `$0` and relative-import semantics. | Cross-repository follow-up |
| MZ-HARD-004 | P1 | Installer | Forced installation followed pre-existing symlinked managed directories. | `scripts/install.sh --force` reused the version root and subdirectories without type checks. | Reject symlinked/non-directory managed roots before writes and add an external-write regression. | Fixed |
| MZ-HARD-005 | P1 | Supply chain | CI built and executed the mutable default branch of `kujolang/kujo`. | `.github/workflows/quality.yml` omitted `ref`. | Pin the runtime checkout to reviewed commit `b8a44653ad9c225e3d31d96c5c1a0d61f9c8d835`. | Fixed |
| MZ-HARD-006 | P1 | Contract | `muzzle run --json` was documented as versioned but emitted no schema discriminator and had no run-result schema. | Baseline JSON lacked `schema_version`; only command/error schemas existed. | Add `muzzle.run/v1`, `command: run`, a strict schema, and regression coverage. | Fixed |
| MZ-HARD-007 | P2 | Documentation | JSON and cleanup examples differed from effective behavior. | The how-to showed raw workflow output as `summary`; the README said cleanup removed all entries. | Align examples with generic summaries, UUID artifact names, lifecycle fields, and recognized-artifact cleanup. | Fixed |
| MZ-HARD-008 | P2 | Dependency contract | The declared Kujo minimum was older than the hardened runtime APIs used by Muzzle. | `kennel.toml` and the how-to claimed 0.1.0 while verification uses Kujo 1.0.0 APIs. | Set the documented and packaged minimum to Kujo 1.0.0. | Fixed |

## Changes Implemented

### Private workflow artifacts

- Problem/root cause: Muzzle preserved potentially sensitive raw output in files created using the ambient umask.
- Implementation: the execution helper privately pre-creates logs, restores the caller's umask before starting the workflow, and the report writer atomically creates verified mode-`0600` Markdown/JSON files.
- Files: `src/muzzle_exec.sh`, `src/report.kujo`, `tests/muzzle_wrapper_regression.sh`, `README.md`, `docs/security.md`.
- Compatibility: CLI output and workflow behavior are unchanged; workflow-created files retain the caller's original umask. The intended change is tighter permissions on Muzzle-owned artifacts.

### Signed-policy byte binding

- Problem/root cause: signature verification and authorization parsing reopened a mutable caller-controlled path.
- Implementation: Muzzle reads the bundle once, writes a private verification snapshot, verifies that snapshot, deletes it, and parses the same original byte string.
- Files: `src/policy.kujo`.
- Tests: existing valid-signature and tamper-denial regressions exercise the revised path; the full wrapper suite passes.
- Compatibility: accepted bundle schema and flags are unchanged. A new `POLICY_BUNDLE_READ` or `POLICY_SNAPSHOT_FAILED` denial provides a controlled fail-closed result for new failure boundaries.

### Installer and CI supply-chain hardening

- Problem/root cause: forced installation trusted existing managed directory types, and CI selected a mutable external revision.
- Implementation: installer rejects symlinked or non-directory managed paths; CI pins Kujo to a full commit SHA.
- Files: `scripts/install.sh`, `tests/muzzle_install_regression.sh`, `.github/workflows/quality.yml`.
- Compatibility: normal fresh/repeated installation behavior is unchanged. Unsafe forced layouts now fail with exit 3.

### Versioned run-result contract

- Problem/root cause: the main automation response contradicted its versioned-contract documentation.
- Implementation: successful and failed workflow reports now include `schema_version: muzzle.run/v1` and `command: run`; a JSON Schema and contract regression were added.
- Files: `src/report.kujo`, `schemas/muzzle-run.schema.json`, `tests/muzzle_wrapper_regression.sh`, `README.md`, `docs/agent-usage.md`, `docs/howto.md`.
- Compatibility: fields are additive; existing field names, types, paths, statuses, and exit codes are preserved. Representative output grew by 48 bytes (463 to 511 bytes).

## Performance & Efficiency

The matching post-change benchmark reported:

| Signal | Before | After | Interpretation |
| -- | --: | --: | -- |
| Startup average | 426 ms | 437 ms | 11 ms local variance; no supported improvement claim |
| Full log size | 4,000,000 bytes | 4,000,000 bytes | Complete evidence preserved |
| JSON summary size | 482 bytes | 531 bytes | +49 bytes for stable schema/command discriminators |
| Peak RSS | 34,648,064 bytes | 34,217,984 bytes | Lower in this sample, but no portable improvement claim |
| Five concurrent runs | 2,614 ms | 2,902 ms | Local variance/permission durability cost; no threshold regression established |

Large-output capture remains bounded and the complete four-megabyte log is preserved. No dependency was added. The run-result discriminator adds a small fixed payload that improves machine routing and compatibility checks.

## Security

Reviewed boundaries included CLI/workflow arguments, manifest parsing, workflow path confinement, runner selection, subprocess argv, timeout/cancellation handoff, raw output/logging, redaction, report/state writes, cleanup deletion, signed policy verification, installer paths, and executable CI dependencies.

Fixed: permissive artifact files, signed-bundle verification/parsing race, forced-install symlink traversal, and mutable CI runtime execution. Regression coverage now verifies private modes and installer confinement. Static traversal, ordinary symlink escape, argument injection, malformed manifest, secret redaction, timeout, cancellation, and process-tree controls continue to pass.

Remaining concern: interpreter execution still reopens a pathname after validation. A compatibility-safe fix needs runtime support that binds the validated file object while preserving script location semantics.

## Compatibility

- Public APIs: no removals or incompatible field changes.
- CLI behavior: existing commands, flags, output fields, exit codes, and artifact naming remain; unsafe forced installation layouts now fail closed.
- File formats/schemas: run JSON gains two additive fields and a new `muzzle.run/v1` schema.
- Config/environment variables: unchanged.
- Runtime dependency: documented minimum Kujo version is now 1.0.0.
- External consumers: tolerant JSON consumers are unaffected; strict consumers must allow the two additive fields. CI now builds the pinned Kujo revision.

## Cross-Repository Follow-Ups

| Repository | Contract | Evidence and impact | Recommended change | Required now | Compatibility concern |
| -- | -- | -- | -- | -- | -- |
| `kujolang/kujo` | Process execution API | Muzzle validates/hashes a script pathname, but Bash/Python/Node/Kujo later reopen it. A concurrent local mutation can defeat checksum/path binding. | Add a descriptor-based or immutable-snapshot interpreter execution primitive with explicit original-path/working-directory semantics. | No; current trusted-local behavior remains, but checksum pins cannot claim race-free binding. | `$0`, relative imports, shebang handling, and platform portability must remain stable. |

## Remaining Work

- P0: none.
- P1: bind validated workflow bytes to interpreter execution after Kujo exposes compatibility-safe support.
- P2: none identified that is both high-confidence and currently worth changing.
- P3: none pursued.
- Needs more evidence: establish stable multi-platform benchmark distributions before adding latency/RSS/concurrency thresholds.
- Not worth changing: arbitrary workflow behavior, inherited workflow environment, raw-log preservation, and external issuer/expiry policy are documented trusted-local or operator-owned contracts.

## Verification Receipt

| Command | Result |
| -- | -- |
| `make quality` (baseline) | Passed |
| `./muzzle --help`; `./muzzle --version`; `./muzzle list` | Passed |
| `MUZZLE_BENCH_ITERATIONS=5 MUZZLE_BENCH_LINES=50000 bash scripts/benchmark.sh` (baseline) | Passed; measurements recorded above |
| `kujo check src/report.kujo && kujo check muzzle.kujo` | Passed |
| `kujo check src/policy.kujo` | Passed |
| `bash -n src/muzzle_exec.sh tests/muzzle_wrapper_regression.sh scripts/install.sh tests/muzzle_install_regression.sh` | Passed |
| `bash tests/muzzle_install_regression.sh` | Passed |
| JSON parsing and schema-discriminator assertion for a real run | Passed |
| Private artifact mode check for a real run | Passed: log, Markdown, and JSON were `0600` |
| `make quality` (completed implementation) | Passed |
| `MUZZLE_BENCH_ITERATIONS=5 MUZZLE_BENCH_LINES=50000 bash scripts/benchmark.sh` (completed implementation) | Passed; measurements recorded above |
| `git diff --check` | Passed |

The canonical implementation and test suite were inspected with broad searches excluding `.dogfood/`, `.muzzle/`, and `.kujo_cache/`. Historical/generated paths were not treated as current product sources.
