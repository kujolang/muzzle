# Muzzle hardening — third pass, 2026-10-10

## Repository and scope

- Repository: `kujolang/muzzle`; branch `main`.
- Starting SHA: `1a1c8c13d518db1e13413932f092754b8b2569fc`, clean.
- Ending implementation SHA: `64fa3e26a6b9e13252ee0332c2742ddfcab6535e`; the following documentation commit records this receipt.
- Purpose: trusted local workflow execution with complete disk evidence and compact agent/human receipts.
- Dependencies/integrations: Kujo, Bash and Unix utilities; optional Python/Node workflow runners, Git/OpenSSL policy checks, Kennel packaging and Eval. Python standard library powers development regressions. No dependency, runtime minimum or sibling source changed.

This continues the [first](repository-hardening-2026-10-10.md) and [second](repository-hardening-2026-10-10-pass2.md) passes. Their repository-wide implementation review remains evidence, rather than restarting from README claims. This round revisited module interfaces, policy/manifest contracts, loop readers and writers, retention/reporting, doctor, runner capture/cleanup, launcher, installation/signing scripts, schemas, package metadata, CI and current/historical documentation. Broad `rg` searches excluded `.dogfood/`, `.muzzle/`, `.kujo_cache/` and `.git/`; evidence reads under ignored audit paths were targeted.

## Baseline and findings

`make quality` passed before implementation: 20 Python test methods in 45.274 seconds, wrapper/process/installer suites, Kujo checks, shell syntax and whitespace. The starting tree was preserved with `git archive HEAD | tar -x -C .muzzle/state/audit-pass3/baseline`. New CLI regressions failed there (five failures including the artifact-preservation assertion); a separate exported-writer probe returned `[true,false]` instead of `[false,false]`, proving malformed data was persisted.

| ID | Priority | Area | Finding | Evidence | Action | Status |
| -- | -- | -- | -- | -- | -- | -- |
| MZ-OCT3-001 | P1 | State integrity | Missing `loop done --note` becomes boolean true, corrupts persisted state, then crashes while reading it. | Both JSON flag orders exited 4 with invalid-index runtime errors; writer probe accepted a boolean note. | Reject missing CLI values and non-string writer note/timestamp inputs before mutation. | Fixed |
| MZ-OCT3-002 | P2 | Argument contract | Opt-in arity validation ignores `allow_extra_args: false` if optional `args` metadata is absent. | Baseline executes unexpected argument and creates artifacts; `args: []` correctly rejects it. | Treat omitted definitions as an empty array while retaining independent arity enforcement. | Fixed |
| MZ-SEP-009 | P1 | Concurrency | Multiple loop writers remain uncoordinated. | Prior reproduced concurrent-start evidence; no writer lock added here. | Retain caller serialization and existing tracking. | Open |

## Changes implemented

### Reject loop values before persistence

Root cause: generic option parsing represents a valueless option as a boolean, and `cmd_loop` passed it to `record_loop_done`. The writer accepted it even though the state reader requires strings. `muzzle.kujo` now emits the existing `OPTION_VALUE_REQUIRED` envelope with exit 2 before finding/mutating the active loop. `src/loops.kujo` rejects non-string note or timestamp arguments from module callers with its existing false failure result.

`test_loop_missing_note_does_not_corrupt_state` checks exported writer behavior, byte-identical state, both missing-note JSON orders, subsequent readable status, literal `--note=--json`, completion and summary. The fixture copies source modules into its temporary project to respect Kujo import confinement. An initial symlink-based fixture was correctly rejected by the runtime and was repaired; no runtime boundary was bypassed. Existing tests cover omitted notes and normal lifecycle. The how-to and changelog describe the corrected contract.

Compatibility: normal string notes and timestamps, omitted notes and explicit empty notes remain valid. Invalid calls now fail before writing. Existing exported signatures, valid state formats and command result schemas are unchanged.

### Enforce zero declared arguments consistently

Root cause: `validate_manifest_args` returned early when `args` was absent, skipping the independent `allow_extra_args` flag. `src/policy.kujo` now defaults definitions to an empty array and continues normal arity validation. A missing manifest still allows arguments. This uses the existing algorithm and errors without a second implementation.

`test_manifest_no_declared_args_enforces_arity` compares omitted/empty definitions, execution/preview, zero arguments, explicitly allowed/default extra arguments and the unchanged opt-in default. Rejected runs create no log artifacts. Workflows documentation and changelog clarify the absent/empty equivalence.

Compatibility: enforcement remains opt-in through `--validate-args`. Explicitly declaring no extra arguments now means the same thing regardless of optional metadata. Existing schemas, argument forwarding, flags and public error fields are unchanged; no migration is needed for valid calls.

## Performance, resources and agent efficiency

These are correctness fixes; no runtime or memory speedup is claimed. The arity path adds only the existing zero-iteration validation and flag check when metadata is absent. Loop checks precede persistence and prevent an invalid write/read cycle. No cache, background work, retry, dependency, schema, model prompt or new tool output was introduced. Existing output spooling, bounded excerpt handling, deterministic artifact ordering and retention behavior remain in place.

Same-host Darwin x86_64, Kujo 1.5.0 benchmark; five startup samples and 50,000 output lines:

| Signal | Before | After |
| -- | --: | --: |
| Startup average | 132 ms | 131 ms |
| Full log bytes | 4,000,000 | 4,000,000 |
| JSON receipt bytes | 531 | 531 |
| Peak RSS bytes | 25,284,608 | 25,452,544 |
| Five concurrent workflows | 1,166 ms | 1,048 ms |

The unchanged evidence/receipt sizes demonstrate preserved output behavior; small unpaired timing/RSS samples do not isolate an improvement or regression. Receipt byte counts measure output footprint, not tokenizer counts. No token estimate or percentage improvement is claimed. Host-local timings are observations, not a performance budget. No timing-sensitive CI gate was added.

## Security and compatibility review

Trust boundaries reviewed include CLI values before persistence, manifest argument validation before workflow execution, loop-state readers/writers, canonical filesystem containment, script/policy trust, and subprocess output/cleanup. This round closes malformed-input state corruption and a declared argument-contract bypass. Muzzle continues to trust local workflow code; neither argument validation nor signed policy creates a sandbox. No new network behavior, credential storage or environment variable was introduced.

Public APIs: signatures unchanged; invalid writer values now return false. CLI: missing note becomes structured exit 2 instead of corrupting state and exiting 4; validated zero-argument contracts now reject extras with existing `ARG_ARITY` exit 2. Formats, schemas and configuration: unchanged. External consumers are affected only if they relied on these invalid inputs. No tests, assertions, safety checks or timeouts were weakened.

Dependency/CI review: action and Kujo source pins remain; there is no new package/install input. This round did not perform an external advisory scan or managed security-service scan. Linux and exact CI-pinned runtime execution were not performed locally. The existing Linux/macOS `make quality` matrix includes the added behavioral tests automatically.

Complexity/dead weight: preserved existing exports and historical evidence where downstream removal safety was unproven. No cosmetic rewrites. Current docs remain the canonical source; historical backlogs are explicitly marked completed.

## Cross-repository follow-ups and remaining work

No cross-repository change is required for either fix. P1: loop writer coordination remains open; callers must serialize loop commands. Newer Kujo file-lock APIs are unavailable in the existing CI pin, so adopting them requires an explicit runtime compatibility decision. Existing SignalBox Capture `cap_07e49865-0784-4f4f-9727-7bbf8b5b610b` and Signal `sig_649f835d-2ac5-4368-8c9c-a396a1d569e0` already track this issue.

P0: none established. P2 / needs more evidence: matched cross-platform resource measurements and exceptionally long physical log lines, as recorded earlier. P3: cosmetic changes not pursued. Not worth changing without evidence: full-log preservation, exported helper compatibility and historical audit artifacts. No new unresolved finding warrants capture; completed fixes belong in Strata. SignalBox: no captures warranted.

## Verification receipt

Logs are local ignored evidence under `.muzzle/logs/audit-pass3/`; baseline checkout and Eval output live in `.muzzle/state/audit-pass3/`.

| Exact command | Result |
| -- | -- |
| `make quality` before changes | Pass: 20 methods plus existing gates |
| `KUJO_BIN=kujo MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-pass3/baseline" python3 tests/muzzle_hardening_regression.py HardeningTests.test_loop_missing_note_does_not_corrupt_state HardeningTests.test_manifest_no_declared_args_enforces_arity` | Expected baseline failures; `negative.log` |
| Same baseline command with only `HardeningTests.test_loop_missing_note_does_not_corrupt_state` after adding direct-writer coverage | Expected boolean-writer failure; `negative-writer.log` |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_loop_missing_note_does_not_corrupt_state HardeningTests.test_manifest_no_declared_args_enforces_arity` | Pass: focused CLI cases |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_loop_missing_note_does_not_corrupt_state` | Pass: repaired direct-writer fixture and CLI cases |

| `make quality` after the corrected test fixture | Pass: 22 methods in 46.663 s, wrapper/process/install suites, Kujo checks, shell syntax and whitespace |
| `KUJO_BIN=kujo bash .muzzle/state/audit-pass3/baseline/scripts/benchmark.sh` | Pass; baseline signals above |
| `KUJO_BIN=kujo bash scripts/benchmark.sh` | Pass; final signals above |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Pass, zero warnings/errors |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- run tests/muzzle_eval.json --output-dir .muzzle/state/audit-pass3/eval --json` | Pass, 4/4 |
| `bash .github/scripts/check-kujo-tool-artifacts.sh` | Pass |
| `git diff --check` | Pass |

No known introduced regression remains. The final quality run uses the corrected copied-module fixture; the initial fixture failure is documented above. The existing CI gate now includes both new test methods without timing thresholds.

## Durable memory and handoff

Strata merged writer-boundary evidence into loop contract `1176bf83-0909-4243-b1a4-8b124e2b21fd` and created arity contract `2e3bfde9-7f07-4b98-9303-904d43094e38`. Both passed exact-ID and conceptual retrieval after batch deduplication. The existing October handoff `1c7d4b5b-0231-4ad0-b3c5-fb0ac87ab97b` receives the final pushed SHA/current state after this report is committed; it preserves the previous timeline and links the atomic contracts. No new SignalBox records: resolved bugs and routine verification were rejected; the already-tracked loop concurrency item is unchanged.
