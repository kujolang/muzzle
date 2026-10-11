# Muzzle hardening — fourth pass, 2026-10-10

## Repository and baseline

Repository `kujolang/muzzle`, branch `main`, starting SHA `d8eff4329e3c093619c51eb0065cc5542a27ec9e`, clean tree. Ending implementation SHA: `ad0dfbdfe79151609e69ea9d02ea72caf5eb4629`; a subsequent documentation commit records the receipt. Muzzle executes trusted local workflows while preserving full evidence and emitting compact receipts. Runtime dependencies remain Kujo, Bash and Unix utilities; optional Git/OpenSSL policy checks, Python/Node runners, Kennel packaging and Eval integration are unchanged.

This continues the [third pass](repository-hardening-2026-10-10-pass3.md) and its linked repository-wide reviews. Baseline `make quality` passed 22 Python methods in 60.091 seconds plus wrapper, process, installation, Kujo checks, shell syntax and whitespace. An immutable baseline was created with `git archive HEAD | tar -x -C .muzzle/state/audit-pass4/baseline`.

## Review coverage

This round traced initialization through every generated file, missing/existing paths, symlink behavior, atomic publication and Git visibility. Also re-inspected info/discovery/integrity resolution, CLI dispatch, installer and shared path helpers. Previous source-level review of runner/resource limits, policy/manifest contracts, redaction/output, retention, loops/concurrency, schemas/dependencies and CI remains applicable. Broad `rg` sweeps excluded `.dogfood/`, `.muzzle/`, `.kujo_cache/` and `.git/`; local evidence reads were targeted. No stale TODO/FIXME/HACK marker was found in the searched active entrypoint/modules/scripts. Historical artifacts and exported compatibility helpers were preserved rather than removed without consumer evidence.

Read-only Kujo source inspection confirmed `write_file_atomic(..., false)` exists in CI-pinned `b8a44653ad9c225e3d31d96c5c1a0d61f9c8d835`: it writes a temporary inode and publishes with a no-overwrite hard link. No sibling files were modified or newer runtime dependency introduced. This is source evidence, not execution of that pinned runtime.

## Findings

| ID | Priority | Area | Finding | Evidence | Action | Status |
| -- | -- | -- | -- | -- | -- | -- |
| MZ-OCT4-001 | P1 | Filesystem security | Init follows dangling generated-file symlinks outside `.muzzle`. | All six leaf fixtures exited 0 and created an outside target at baseline. | Atomic no-overwrite creation through one helper; controlled failure. | Fixed |
| MZ-OCT4-002 | P2 | Local evidence hygiene | Generated ignore rules omit loop state and temporary policy snapshots. | Two `git check-ignore` baseline failures; other state/artifact rules work. | New projects ignore all `state/`; preserve custom existing rules and document migration. | Fixed |
| MZ-SEP-009 | P1 | Concurrency | Loop writers remain uncoordinated. | Prior concurrent-start reproduction; this pass changes no loop locking. | Retain caller serialization and existing follow-up. | Open |

## Changes implemented

### Atomic initialization

Root cause: `file_exists` follows a symlink and reports false for a dangling target; ordinary `write_file` then follows that same link during creation. The session file also permitted overwrite after the check. `initialize_file` in `muzzle.kujo` now preserves existing files and uses `write_file_atomic(path, content, false)` for new ones. A conflicting leaf cannot be followed or overwritten during publication, including one appearing after the existence check. Failure names the affected path and exits 1 through `INIT_WRITE_FAILED`; init retains its established text-only output.

The helper covers both example workflows, both manifests, session state and `.muzzle/.gitignore`, removing six duplicated check/write blocks. Partial initialization may leave successfully created files; retry preserves them. This is atomic per-file publication, not a whole-directory transaction. Existing ancestor checks remain; no hostile same-user ancestor-swap isolation guarantee is claimed.

`test_init_never_follows_dangling_generated_file_links` covers all six destinations: exit 1, no runtime stderr, actionable message, outside target absent, link preserved and temporary files cleaned. It also checks existing user contents through partial initialization and normal repeated-init behavior. Baseline: six failures. README, how-to, security guidance and changelog describe affected behavior.

### Local-state ignore coverage

Root cause: a narrow list ignored session bookkeeping/execution snapshots but missed other generated state. New `.muzzle/.gitignore` files use `state/` alongside `logs/` and `reports/`. `test_init_ignores_local_state_but_preserves_workflow_tracking` runs real Git checks for loop notes, policy snapshots, session/lock/execution files, logs and reports, while proving workflows, manifests and ignore rules remain trackable. Global exclude rules are disabled for those fixture checks. The test also verifies custom ignore files survive partial initialization.

Existing projects are not silently rewritten. Add `state/` to older `.muzzle/.gitignore` files; ignore rules do not untrack committed files. The README diagram now locates the generated ignore file correctly inside `.muzzle`, without claiming init creates a root cache-ignore rule.

## Performance and efficiency

No speedup, memory reduction or token savings is claimed. Atomic publication adds file synchronization during first/partial initialization to protect data integrity; startup/run execution paths are unchanged. Initialization has six fixed outputs, no new cache, traversal, retry or background process. One helper replaces repeated unsafe writes without introducing an abstraction layer. No dependency, tool schema, prompt or model-visible run payload changed. Full evidence remains on disk.

Same-host Darwin x86_64 / Kujo 1.5.0 measurements (five startup samples, 50,000 output lines):

| Signal | Before | After |
| -- | --: | --: |
| Startup average | 241 ms | 173 ms |
| Full log bytes | 4,000,000 | 4,000,000 |
| JSON receipt bytes | 531 | 531 |
| Peak RSS bytes | 27,729,920 | 26,173,440 |
| Five concurrent workflows | 1,363 ms | 1,441 ms |

These noisy, unpaired samples measure ordinary startup/run behavior, not isolated initialization latency or causal improvement. Receipt bytes are not tokenizer counts. No flaky timing ratchet was added.

## Security and compatibility

Reviewed trust boundaries: fixed initialization destinations versus repository-controlled symlinks, existing user files, managed parent paths, generated state versus tracked source, and runtime atomic-write semantics. The reproduced out-of-tree creation is fixed with regressions. Init now fails safely for dangling destination symlinks; it does not overwrite or remove them. Muzzle remains a trusted-local runner, not a sandbox. Existing full logs may contain sensitive data and remain owner-only as previously implemented.

Public APIs: unchanged; new init helper is private. CLI: normal init/no-op text remains; creation conflicts now produce controlled exit 1 rather than outside writes or raw failures. File formats and JSON schemas: unchanged. Configuration: newly generated `.muzzle/.gitignore` broadens state exclusion; existing rules remain untouched. Environment variables: unchanged. Consumers of valid initialization retain compatibility. No minimum runtime or dependency change. No external advisory scan or managed security scan was run. Linux and the exact pinned runtime were not executed locally.

## Remaining work and cross-repository follow-ups

No sibling change is required. P1: caller serialization remains necessary for loop commands; adopting newer Kujo file-lock APIs requires a deliberate runtime/CI compatibility decision. Existing SignalBox Capture `cap_07e49865-0784-4f4f-9727-7bbf8b5b610b` and Signal `sig_649f835d-2ac5-4368-8c9c-a396a1d569e0` already track that issue. P0: none established. P2 / needs more evidence: matched cross-platform performance and pathological physical log-line resource use, as previously recorded. P3: no cosmetic rewrite. Not worth changing without evidence: historical artifacts, exported helpers, supported trusted-workflow behavior or full-log preservation.

Both new findings are resolved; no new unresolved high-signal item was admitted. SignalBox: no captures warranted. Durable completed-work contracts and handoff belong in Strata.

## Verification receipt

Local verbose evidence: `.muzzle/logs/audit-pass4/`. Baseline and Eval artifacts: `.muzzle/state/audit-pass4/`.

| Exact command | Result |
| -- | -- |
| `make quality` before edits | Pass; 22 methods plus existing suites/checks |
| `KUJO_BIN=kujo MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-pass4/baseline" python3 tests/muzzle_hardening_regression.py HardeningTests.test_init_never_follows_dangling_generated_file_links` | Expected baseline failure: six cases |
| `KUJO_BIN=kujo MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-pass4/baseline" python3 tests/muzzle_hardening_regression.py HardeningTests.test_init_ignores_local_state_but_preserves_workflow_tracking` | Expected baseline failure: loop/policy state not ignored |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_init_never_follows_dangling_generated_file_links HardeningTests.test_init_ignores_local_state_but_preserves_workflow_tracking` | Pass, two methods |
| `make quality` after edits | Pass: 24 methods in 71.013 seconds plus wrapper/process/install suites, Kujo checks, shell syntax and whitespace |
| `KUJO_BIN=kujo bash .muzzle/state/audit-pass4/baseline/scripts/benchmark.sh` | Pass; baseline signals above |
| `KUJO_BIN=kujo bash scripts/benchmark.sh` | Pass; final signals above |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Pass |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- run tests/muzzle_eval.json --output-dir .muzzle/state/audit-pass4/eval --json` | Pass, 4/4 |
| `bash .github/scripts/check-kujo-tool-artifacts.sh` | Pass |
| `git diff --check` | Pass |

No known introduced regression remains. The existing Linux/macOS quality matrix automatically includes both added behavioral tests. No safety checks, assertions or timeouts were weakened.

## Durable record

Strata saved atomic initialization contract `d3675562-e58d-4ba7-a38b-8e86002baa7a` and local-state ignore contract `02bb2478-586c-4810-8580-1dfc487f8c77` after batch deduplication. Both passed exact-ID and conceptual retrieval. The existing October handoff `1c7d4b5b-0231-4ad0-b3c5-fb0ac87ab97b` is updated with the final pushed SHA after this report is committed, retaining prior timeline entries and linking these contracts. Completed fixes and routine verification were rejected from SignalBox capture.
