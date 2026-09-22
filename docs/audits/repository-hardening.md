# Repository Hardening Audit — September 2026

## Repository and scope

- Repository: `kujolang/muzzle`; branch: `main`.
- Starting SHA: `ac40faf465486848509275cdd5f3af8096bbdeea`, clean working tree.
- Ending implementation SHA: `9733aa48aef90b6ad5d444d1485014ead5b4f398` (the following documentation commit records this receipt).
- Purpose: trusted-local workflow execution with complete disk evidence and concise human/agent receipts.
- Dependencies: Kujo (declared minimum 1.0.0), Bash 3.2+, Unix utilities, SHA-256 utility; optional Python/Node workflow runners, Git safety checks, OpenSSL signatures. No package dependency added. Python 3 standard library is now required for the development hardening tests, not Muzzle execution.
- Integrations: stable CLI/JSON consumers (Dispatch/MCP and other ecosystem tools); optional Kujo Eval adapter; Kennel packaging. No sibling repository was modified.
- Environment: macOS Darwin x86_64; local Kujo 1.4.0. Linux execution remains the existing CI matrix's responsibility; this session did not run Linux or rebuild the pinned CI runtime.
- Prior audit: [August report](repository-hardening-2026-08.md), retained unchanged. September observations supersede its statements that no P1 work remains.

Broad searches used `rg`/`rg --files`, excluding `.dogfood/`, `.muzzle/`, `.kujo_cache/`, and `.git/`. Explicit evidence reads under `.muzzle/state/audit-2026-09/` were separate from canonical source review.

## Baseline

`make quality` passed before implementation: Kujo source checks, shell syntax, whitespace, wrapper, process lifecycle, and installer suites. Baseline failures were then demonstrated with the newly added targeted tests against an immutable `git archive` of the starting SHA. These reproduced long-key disclosure, oversized excerpts, non-JSON repeated starts, masked lint errors, per-entry snapshot process creation, and discovery name/path errors. Existing green tests did not cover those cases.

Baseline logs and the extracted checkout are local ignored artifacts under `.muzzle/state/audit-2026-09/`. The exact long-key reproduction exited 4 and exposed `PRIVATE-BODY-77` through `PRIVATE-BODY-80` in the JSON excerpt. No real credentials were used.

## Review coverage

| Surface | Review and conclusion |
| -- | -- |
| Entrypoint/CLI | Read launcher, dispatch, option parsing, exits, help, dry-run, JSON contracts, completions and tests. Existing flags and command aliases retained. |
| Execution/resources | Read runner/helper, process capture limits, digest snapshots, signal forwarding, cleanup, log spooling and benchmarks. Optimized sibling linking; retained process-tree and integrity protections. |
| Filesystem/state | Reviewed init, private reports, manifest confinement, retention deletion, installer checks, session bookkeeping and loop transitions. Tightened discovery and loop validation; confirmed unresolved loop writer race. |
| Security | Reviewed argv boundaries, trusted workflow/environment model, manifests, signed bundles, checksums, permissions, excerpt redaction, timeout/cancellation and symlink tests. Long multiline secret disclosure fixed. No sandbox claim. |
| API/dependencies | Read schemas, Kennel metadata, signing/install scripts, CI action/runtime pins, package layout and integrations. No new runtime package; scanner shipped by installer and Kennel `src` inclusion. |
| Agent/context/output | Reviewed README, agent guide, how-to, workflows, security, performance, instructions, examples and historical evaluation. Compact result fields and full evidence remain. No new prompts, model calls or MCP schemas. |
| Complexity/dead weight | Reused one validated manifest per execution; fixed suffix derivation rather than introducing another discovery abstraction. Historical evaluation and exported helpers retained because removal lacked consumer evidence. |
| Regression ratchets | Existing Linux/macOS `make quality` now includes targeted Python behavioral tests. Deterministic process-count gate replaces fragile timing thresholds. |

## Findings

| ID | Priority | Area | Finding/evidence | Action | Status |
| -- | -- | -- | -- | -- | -- |
| MZ-SEP-001 | P1 | Security | `tail -n 40` discarded distant BEGIN markers before redaction; 80-line key body leaked in JSON. | Stream redaction before selecting five lines; share the Kujo pattern catalog with awk; test all nine block formats, closed/unclosed. | Fixed |
| MZ-SEP-002 | P1 | Performance | One external `ln` per sibling; baseline test fixture invoked 274 link processes. | Batch at most 64 sources / approximately 16 KiB per invocation; test <=10 calls for the same fixture. | Fixed |
| MZ-SEP-003 | P1 | CI | The shell loop in `make lint` returned only its last check's status. | Propagate every failed Kujo check immediately; a stub failing `src/cli.kujo` proves the gate fails. | Fixed |
| MZ-SEP-004 | P2 | State/contract | Repeated `loop start --json` returned prose; nested invalid entries passed validation; writes could expose partial JSON. | Return the existing JSON state, validate entry shapes/sequence and scalar types, replace state atomically. | Fixed; writer coordination remains separate |
| MZ-SEP-005 | P2 | Discovery | Global suffix replacement renamed `build.sh.sh` to `build`; directories and escaping scripts appeared as workflows. | Remove only the final suffix; require valid names and confined regular files. | Fixed |
| MZ-SEP-006 | P2 | Consistency/efficiency | Execution read the same manifest three times, allowing inconsistent metadata within one command. | Reuse the validated manifest for script resolution, policy, runner and integrity; preserve the existing resolver entrypoint. | Fixed |
| MZ-SEP-007 | P2 | Failure handling | Unreadable manifests could escape as runtime failures. | Return structured `MANIFEST_READ`, tested using a directory at a manifest filename. | Fixed |
| MZ-SEP-008 | P2 | Developer experience | Eval suite hardcoded one developer's checkout. | Use repository-relative commands/paths; document isolated module resolution for optional Eval runs. | Fixed |
| MZ-SEP-009 | P1 | Concurrency | Eight simultaneous starts created eight active loop files. Atomic writes do not serialize the state machine. | Document caller serialization; preserve evidence and a SignalBox review item. | Open |

## Changes implemented

### Redaction and output bounds

Root cause: the bounded log-tail optimization occurred before stateful multiline redaction. `src/redact_log.awk` now scans the complete log with patterns supplied by `src/redact.kujo`, retaining five redacted lines. Ordinary diagnostics remain available, including lines after closed blocks. Lines above 4,096 characters receive an explicit omission notice; original bytes remain in the log. Failed or truncated scanner results produce an explicit unavailable-excerpt notice. The scan keeps the existing five-second helper deadline.

Files: `src/redact_log.awk`, `src/redact.kujo`, `src/runner.kujo`, `muzzle.kujo`, installer, install regression and focused regression suite. All nine supported block formats have closed and unclosed long-block tests. One-megabyte lines test redaction, explicit bounds and exact raw-log preservation. Installed execution verifies that the scanner is shipped.

Compatibility: field names, result schemas and workflow exit codes are unchanged; excerpts change where the prior behavior leaked secrets or exposed oversized lines. Failure scanning now performs O(log bytes) work. The retained excerpt is bounded; awk's input record allocation can still grow with the longest physical line. Arbitrary raw logs remain sensitive and owner-only.

### Snapshot preparation

Root cause: `link_directory_except` spawned one process for each directory entry. It now constructs bounded arrays for portable BSD/GNU `ln`, keeping absolute source paths, hidden entries, whitespace/newline names, dangling symlinks and exclusion rules. Failures still abort preparation and clean the snapshot. Digest verification, byte-bound execution, runner identity and private modes are unchanged.

Files: `src/muzzle_exec.sh`, `scripts/benchmark-snapshot.py`, targeted tests and performance documentation. The benchmark uses two warmups plus ten alternating measured samples for each checkout/workload, verifies output and cleanup, and records all raw samples in [benchmark data](2026-09-snapshot-benchmark.json). Existing pre/post-snapshot mutation and process lifecycle regressions pass.

### State, discovery and quality gates

Files: `src/loops.kujo`, `src/workflow.kujo`, `muzzle.kujo`, `Makefile`, `tests/muzzle_hardening_regression.py`, `tests/muzzle_eval.json`, contributor documentation and changelog.

- Valid existing loop state remains accepted. Hand-edited malformed scalar/entry data now receives `LOOP_STATE_INVALID` without mutation; generated state uses atomic replacement.
- Repeated JSON loop starts preserve the existing limit/current values and emit the normal `muzzle.loop/v1` start envelope. Text output is unchanged.
- Discovery preserves names containing repeated extensions and excludes directories/escaping scripts that execution cannot safely run.
- `cmd_run` manifest reads fall from three to one (source-supported count, not a measured wall-time claim); discovery/info also reuse already loaded metadata where applicable.
- An early Kujo lint failure can no longer be masked by a later success. New tests join the existing quality target and require only Python's standard library.

## Performance and efficiency

Matched helper timings, local medians in milliseconds (10 measured samples per row):

| Project root entries | Before | After |
| --: | --: | --: |
| 0 | 238.04 | 225.19 |
| 100 | 1,113.81 | 314.42 |
| 1,000 | 10,555.54 | 1,150.81 |

These measure the snapshot helper, not complete end-to-end CLI startup. Filesystem/host noise remains; no portable percentage or SLA is claimed.

Existing benchmark, same host/runtime, five startup and concurrent runs, 50,000 output lines:

| Signal | Before | After | Interpretation |
| -- | --: | --: | -- |
| Startup average | 188 ms | 170 ms | Small sample; no startup improvement claim |
| Full log | 4,000,000 bytes | 4,000,000 bytes | Evidence unchanged |
| JSON receipt | 531 bytes | 531 bytes | Contract/output footprint unchanged |
| Peak RSS | 26,562,560 bytes | 25,395,200 bytes | Host-local observation; no memory improvement claim |
| Five concurrent workflows | 2,241 ms | 1,593 ms | Supporting local signal, not an isolated causal benchmark |

No token count was measured and no token-saving claim is made. Receipt byte counts are not tokenizer counts. No package dependency was added. This interpreted CLI has no separate repository binary/build-size gate. Raw-log retention remains operator-controlled through `clean`; `--keep` ranking is quadratic by inspection and requires scale evidence before redesign.

## Compatibility and security boundaries

- Public APIs: existing exported functions retained; internal manifest resolver added.
- CLI: commands, aliases, flags, normal exit propagation, JSON fields and artifact naming preserved. Previously invalid paths/state now fail earlier. Repeated JSON start now conforms to its intended contract.
- Formats/schemas/config/environment: no serialized format or schema change; no production configuration/environment variable added. Optional Eval documentation uses the runtime's existing isolated-import setting.
- Runtime requirements: no minimum-version bump. Awk was already used by the snapshot helper and is now explicitly documented. Python 3 is a development test dependency only.
- External consumers: successful run receipts remain the same size/shape; consumers must not depend on leaked secret tails, malformed states, or unrunnable discovery entries.
- Workflow scripts and sibling imports remain trusted local code. Same-user hostile mutation, raw-log secrets, arbitrary workflow networking and terminal output in verbose mode remain outside isolation guarantees.

## Cross-repository follow-ups

No sibling change is required for the shipped fixes. A loop-lock design must account for the supported Kujo runtime: CI-pinned `b8a44653ad9c225e3d31d96c5c1a0d61f9c8d835` lacks newer `file_lock`/`file_unlock`. Adopting those APIs would require an explicit minimum-runtime and CI-pin migration, or an independently verified compatible lock implementation. Neither change was hidden in this pass.

The optional Eval invocation initially failed in both VM and interpreter modes because cwd-based `src.report` resolution selected Muzzle's module (`Symbol 'save_report' not found`). Kujo 1.4.0's `KUJO_ISOLATED_IMPORTS=1` resolves this without modifying Eval or Kujo; it is documented for this optional integration.

## Remaining work

- P0: none established.
- P1: MZ-SEP-009, serialize loop state transitions. Until then, use one loop writer per project. Reproduce by starting eight distinct workflows concurrently in a newly initialized project, then counting active `.muzzle/state/loops/*.json` files; this session observed eight. Snapshot/log execution remains independently concurrent.
- P2 / needs more evidence: retention ranking at large artifact counts; external awk memory on exceptionally long single-line logs; matched Linux performance and pinned-runtime execution. No flaky timing gates added.
- P3: no cosmetic rewrite pursued.
- Not worth changing without evidence: historical evaluation artifacts, public helper exports, raw-log preservation, trusted workflow environment, or issuer/expiry policy owned by the operator.

SignalBox: Capture `cap_07e49865-0784-4f4f-9727-7bbf8b5b610b`, Signal `sig_649f835d-2ac5-4368-8c9c-a396a1d569e0`, both for loop writer coordination. Exact-ID and concept retrieval passed; no duplicates found. Completed fixes, routine verification and unsupported hypotheses were rejected from capture.

## Verification receipt

Commands ran from the Muzzle root unless noted. Initial log redirects used `.muzzle/audit-2026-09/`; those artifacts were subsequently moved under ignored state.

| Exact command / check | Result |
| -- | -- |
| `make quality` before changes | Passed |
| `KUJO_BIN=kujo MUZZLE_BENCH_ITERATIONS=5 MUZZLE_BENCH_LINES=50000 bash scripts/benchmark.sh` before and after | Passed; values above |
| `MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-2026-09/baseline-repo" KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py` | Failed as expected against original code: 22 subtest failures and one JSON parse error; proves new regression coverage |
| Same baseline command with `HardeningTests.test_discovery_names_and_regular_file_boundary` | Failed as expected: `build.sh` missing from listing |
| `kujo check src/runner.kujo`; `kujo check src/loops.kujo`; `kujo check src/workflow.kujo`; `kujo check muzzle.kujo` | Passed |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py` | Passed; six test methods including 18 long-block subcases in final gate |
| `bash tests/muzzle_process_regression.sh` | Passed, also rerun by final gate |
| `python3 scripts/benchmark-snapshot.py --baseline .muzzle/state/audit-2026-09/baseline-repo --output docs/audits/2026-09-snapshot-benchmark.json` | Passed; 72 samples including warmups, output/cleanup assertions for all |
| `make quality` after implementation | Passed: all Kujo checks, shell syntax, whitespace, wrapper/process/install suites, six new behavioral tests |
| `kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Failed due to cwd module collision; not caused by suite contents |
| `kujo run ../eval/main.kujo --interpreter -- lint tests/muzzle_eval.json` | Same module collision; interpreter warnings also retained locally |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Passed, zero warnings/errors |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- run tests/muzzle_eval.json --output-dir .muzzle/state/audit-2026-09/eval --json` | Passed, 4/4 in 54,951 ms |
| Eight parallel `muzzle loop start concurrent-N --json` commands | Confirmed open issue: eight active loop states |
| `bash .github/scripts/check-kujo-tool-artifacts.sh` | Passed |
| `git diff --check` | Passed |

The first streaming-redactor attempt failed on BSD awk because literal newlines in `-v` values are rejected. Using a delimiter in the shared pattern catalog fixed the cause; all subsequent redaction tests passed. No assertion, timeout, or safety check was weakened.

Verbose evidence is retained locally in `.muzzle/state/audit-2026-09/logs/`; matched performance samples are committed alongside this report. Baseline extracted files and generated workflow logs are not committed.
