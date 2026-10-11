# Repository hardening — 2026-10-10

## Repository

- Repository: `kujolang/muzzle`; branch: `main`, initially clean.
- Starting SHA: `fa185d62fd7abb4a5e6577f9aa76df9cdfbfd998`.
- Ending implementation SHA: `136490a18084447943690e63beb82bb45d51ad23`. The subsequent audit commit records this report; obtain that commit with `git log -1 -- docs/audits/repository-hardening-2026-10-10.md`.
- Purpose: trusted-local workflow execution with complete disk logs, concise receipts, optional approval/integrity checks, and persistent agent-loop state.
- Host: macOS Darwin x86_64, Kujo 1.5.0. Runtime dependencies remain Kujo, Bash and Unix utilities; Python/Node runners and OpenSSL signing are optional. Development tests/paired benchmarks use Python's standard library. No dependency was added or upgraded.
- Integration contracts: launcher and direct Kujo entrypoint, Kennel package layout, optional Eval suite, CLI consumers such as Dispatch/MCP adapters, manifests and versioned JSON. No sibling repository was modified.

Broad searches used `rg`/`rg --files`, excluding `.dogfood/`, `.muzzle/`, `.kujo_cache/` and `.git/`; historical `evaluation/` data was excluded from primary source sweeps. Explicit reads of prior audits and local evidence were separate. The immutable baseline archive is `.muzzle/state/audit-2026-10-10/baseline/`; verbose evidence is under `.muzzle/logs/audit-2026-10-10/`.

## Baseline

Before production edits, `make quality` passed Kujo checks, shell syntax, whitespace, wrapper contracts, process lifecycle, installation, and all ten existing Python methods (54.992 seconds for that Python suite). There were no failures in the existing gate.

New behavioral probes against the starting archive exposed failures absent from that gate: option values activating flags; external policy-state access; six cleanup ancestor/mode combinations; malformed artifact inspection; newline script execution; destructive short cleanup preview; false-success benchmark reporting; and lost helper diagnostics after a same-line secret block. The initial five-method probe reported ten failing cases; separate preview, benchmark, and redaction probes each failed. No real credentials or external services were used.

General baseline: five startup samples averaged 194 ms; 50,000 output lines produced a 4,000,000-byte log and 531-byte JSON receipt; observed peak RSS was 27,783,168 bytes; five concurrent workflows took 1,816 ms. These are host-local signals, not service guarantees.

## Review coverage

| Surface | Evidence and disposition |
| --- | --- |
| Contracts/architecture | Read entrypoint, wrapper, all `src` modules, manifests/schemas, package/spec metadata, examples and command tests. Kept commands, aliases, supported runners, serialization fields and execution precedence. |
| Complexity/runtime | Found repeated full argv scans with inconsistent token ownership; replaced them with one parser. Reviewed discovery metadata reads, retention ranking, snapshot links, startup and subprocess dispatch. Avoided speculative caching or restructuring of the large entrypoint. |
| Memory/resources | Kept direct log spooling, bounded runtime capture, deadline-bound streaming redaction and explicit retention. No new persistent cache; parser maps have a fixed option vocabulary. Workflow argument storage remains proportional to input. |
| Output/agent context | Reviewed README, agent guide, howto, workflows, security/performance docs, instructions and context-comparison procedure. Full logs remain on disk; JSON byte footprint is unchanged. No model calls, prompts, provider payloads or MCP schemas exist in the execution path. |
| Errors/state | Reviewed manifest parsing, helper failures, reports, cleanup, session lock and loop transitions. Fixed filtered-list crashes, hidden benchmark failures and dropped redacted diagnostics. Existing best-effort session bookkeeping and single-writer loop limitation remain explicit. |
| Security | Independent source review plus local behavioral regressions covered literal argv, policy approval, signed snapshots, checksum binding, symlink confinement, cleanup, redaction, permissions and process trees. Fixed boundary gaps without claiming sandbox isolation. |
| Dependencies/CI | Read installer/signer, Makefile, pinned CI actions/runtime, artifact guard and optional Eval adapter. Added tests to the existing Linux/macOS gate; no timing threshold or new package. Did not perform an online CVE census or change dependency versions. |
| Dead weight | No proven removable public exports or historical artifacts. Preserved compatibility helpers, examples and evaluation evidence. Removed only two private run-option scanners superseded by the unified parser. |

## Findings

| ID | Priority | Area | Finding / evidence | Action | Status |
| --- | --- | --- | --- | --- | --- |
| MZ-1010-01 | P1 | Policy / CLI | `--cancel-file --approve` activated approval; consumed `--dry-run`/`--json` values also changed modes. Separate scans disagreed with positional parsing. | Parse option ownership once; consume values; preserve first-value wins and `--`. | Fixed |
| MZ-1010-02 | P1 | Destructive command | `clean -n --json` deleted three artifacts because the generic parser ignored short flags. Review also found `--json -n` consumed `-n`. | Recognize all clean boolean flags without consuming the next token; test both orders. | Fixed |
| MZ-1010-03 | P2 | State boundary | Signed-policy verification followed an external state symlink before any execution-state check, even on dry-run. | Validate state before snapshot creation and OpenSSL invocation. | Fixed |
| MZ-1010-04 | P2 | Cleanup boundary | Helper cleanup modes ran before ancestor symlink checks; matching owner markers allowed externally redirected deletion. | Check root/state/execution ancestors before scanning or deleting. | Fixed |
| MZ-1010-05 | P2 | Artifact inspection | Filtered listing parsed invalid/overflow timestamps without handling exceptions; filtered logs and reports could follow external file symlinks or inspect directories. | Guard timestamp parsing and require confined regular files in every listing path. | Fixed |
| MZ-1010-06 | P2 | Runner compatibility | Line-based Bash `read` truncated newline paths; filename-bearing SHA utilities escaped their digest output for such names. | Split only on `/`; hash through stdin. | Fixed |
| MZ-1010-07 | P2 | Diagnostics | The in-memory redactor treated a same-line BEGIN/END block as unterminated and swallowed later useful diagnostics. | Match the streaming scanner's same-line closure semantics. | Fixed |
| MZ-1010-08 | P2 | Measurement correctness | Bare shell `wait` returned success despite failed concurrent benchmark workflows. | Wait for every captured PID and reject the benchmark if any failed. | Fixed |
| MZ-SEP-009 | P1 | Concurrency | Loop state still uses unlocked read/modify/write; prior audit reproduced multiple active loops. | Preserve documented single-writer restriction and existing SignalBox record. | Existing open issue |

## Changes implemented

### One source of truth for run arguments

`muzzle.kujo` now returns workflow, literal arguments, options and missing-value information from one traversal. The old presence/value scanners were private and are removed. Missing-value diagnostics retain their existing codes and order; runner precedence, first-value wins, `execute` alias and delimiter behavior remain covered. Consumed option values no longer activate approval, verbose, dry-run or JSON modes. `src/cli.kujo` separately recognizes clean's three boolean spellings without consuming adjacent flags.

Seven Python test methods were added, and the existing helper-diagnostic test gained a same-line block case. The CLI tests exercise mode-shaped values, actual execution versus preview, approval denial without artifacts, literal arguments, repeated runner values and both short-preview flag orders. These are behavioral checks rather than parser implementation snapshots.

### Consistent state and inspection boundaries

`src/policy.kujo` rejects a missing, nondirectory or externally resolving state directory with additive code `POLICY_STATE_UNSAFE`, exit 3. A fake verifier proves it is never invoked through the rejected symlink; the external directory remains untouched. Valid policy signatures and tamper denials remain covered by the existing wrapper suite.

`src/muzzle_exec.sh` shares ancestor checks across execution and both cleanup entrypoints. Tests cover `.muzzle`, `.muzzle/state` and `.muzzle/state/executions` symlinks with matching owner markers and assert sentinel preservation. Normal snapshot cleanup, timeout, cancellation and forwarded interruption retain their existing process tests.

Artifact inspection uses one confined-regular-file predicate in filtered/unfiltered log/report paths. Filtered timestamp conversion handles malformed and overflowing input as nonmatching entries. Listings still preserve sorted order, fields, byte sizes and exact workflow matching; arbitrary regular unfiltered `.log`/`.md` names remain visible. No artifacts are renamed or removed by inspection.

### Useful evidence and measurement

Snapshot path components are split with Bash parameter expansion, preserving embedded newlines; stdin hashing avoids filename escaping in checksum output. The new nested-newline workflow test checks the complete log and snapshot cleanup. This does not claim support for every exotic operating-system pathname or a new sandbox boundary.

`src/redact.kujo` closes a secret block whose END marker occurs on the opening line; the line remains redacted and subsequent useful diagnostics survive. Existing multiline, unterminated, oversized and full-log-preservation tests remain intact.

`scripts/benchmark.sh` now records and checks every concurrent PID. An injected runtime fails only concurrent workflows; the test requires a failed benchmark with no success receipt. `scripts/benchmark-arguments.py` adds optional paired measurements with semantic assertions. Documentation covers token ownership, safe inspection, preview and policy-state behavior, and corrects stale wrapper interpreter-mode descriptions.

## Performance and efficiency

Matched dry-run measurements use the same runtime and initialized temporary project, one warmup and five alternating samples per checkout/size. Every sample asserts exact args/runner/workflow, parseable JSON, empty stderr and no execution artifacts. Raw samples: [argument benchmark](2026-10-10-arguments-benchmark.json).

| Workflow arguments before options | Baseline median | Candidate median |
| ---: | ---: | ---: |
| 0 | 441.28 ms | 241.69 ms |
| 25 | 1,991.03 ms | 395.58 ms |
| 100 | 6,465.03 ms | 867.74 ms |

The source eliminates repeated argv traversals; these paired observations support reduced dry-run overhead for the measured inputs. They are not portable latency budgets. An exploratory 1,000-argument run was stopped after unexpectedly long baseline execution; no incomplete sample was used. Defaults use 0/25/100 representative argument counts. Host activity can affect absolute times.

| General signal | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Startup average, five samples | 194 ms | 144 ms | No isolated startup claim |
| Full log bytes, 50,000 lines | 4,000,000 | 4,000,000 | Evidence preserved |
| JSON receipt bytes | 531 | 531 | Success footprint unchanged |
| Observed peak RSS bytes | 27,783,168 | 26,234,880 | No isolated memory claim |
| Five concurrent workflows | 1,816 ms | 1,128 ms | Host-local signal only |

No tokenizer was run: bytes are not token counts. No new dependencies, model calls, tool schemas, logs or eager agent context were added. There is no independently built Muzzle binary to compare. No validation was removed for speed, and no timing assertion was added to CI.

## Security and compatibility

The relevant attacker/input surfaces are supplied CLI tokens, preexisting filesystem layouts, local manifests/policy files, workflow output, and state artifacts. Scripts and environment remain trusted local code. This pass fixes approval-token confusion, unsafe state paths and inspection inconsistencies; it does not establish remote exposure or privilege escalation. Isolation from hostile same-user mutation remains outside the model. Full logs remain sensitive and are deliberately preserved.

- Public APIs/exports: unchanged; no exported helper was removed.
- CLI: existing commands/options/aliases remain. Consumed values no longer act as flags; short cleanup preview now previews in either JSON-flag order. These correct unsafe behavior, with no migration for ordinary invocations.
- JSON/file formats/schemas/configuration/environment: unchanged. `POLICY_STATE_UNSAFE` is an additive error code within `muzzle.error/v1`. Existing scripts/manifests need no rewriting.
- Artifact inspection: unsafe symlinks/directories are skipped; invalid filtered timestamps no longer crash. Legitimate file paths and receipt fields stay intact.
- External consumers: no ecosystem-wide change required. Callers must pass `--approve` as an option rather than rely on a filename accidentally granting approval.

## Cross-repository follow-ups and remaining work

- P0: none established.
- P1: existing loop-writer coordination remains open. Callers must serialize `loop start/next/done`. A process-lifetime locking design needs deliberate compatibility review: the pinned CI Kujo revision predates newer `file_lock` APIs. No sibling runtime change is required by this patch.
- P2 / needs more evidence: Linux and the CI-pinned runtime were not run locally; existing CI covers both supported OS families. Extremely long awk records can allocate memory proportional to physical line length. Real disk exhaustion and hardware failure were not simulated.
- P3 / not worth changing: cosmetic module splitting, exported compatibility helpers, historical evaluation assets, and trusted-local environment inheritance without evidence of a contract bug.
- Operator-owned: policy issuer/expiry handling, key custody and retention limits remain documented responsibilities.

SignalBox concept search and exact lookup confirmed existing Capture `cap_07e49865-0784-4f4f-9727-7bbf8b5b610b` / Signal `sig_649f835d-2ac5-4368-8c9c-a396a1d569e0`. The loop finding was skipped as a duplicate. Completed fixes and routine verification were rejected as capture candidates. SignalBox: no captures warranted.

## Verification receipt

| Exact command / probe | Result |
| --- | --- |
| `make quality` before changes | Passed; `baseline-quality.log`, ten Python methods |
| `KUJO_BIN=kujo MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-2026-10-10/baseline" python3 tests/muzzle_hardening_regression.py HardeningTests.test_run_option_values_never_activate_flags HardeningTests.test_policy_snapshot_rejects_external_state HardeningTests.test_cleanup_rejects_symlinked_ancestors HardeningTests.test_artifact_inspection_skips_unsafe_and_malformed_entries HardeningTests.test_snapshot_preserves_newlines_in_script_path` | Failed as intended; ten cases, `negative-tests.log` |
| Same baseline environment, `python3 tests/muzzle_hardening_regression.py HardeningTests.test_short_cleanup_preview_never_deletes_artifacts` | Failed as intended; `negative-clean-preview.log` |
| Same baseline environment, `python3 tests/muzzle_hardening_regression.py HardeningTests.test_benchmark_rejects_failed_concurrent_workflows` | Failed as intended; `negative-benchmark.log` |
| Same baseline environment, `python3 tests/muzzle_hardening_regression.py HardeningTests.test_helper_diagnostics_are_redacted_and_bounded` | Failed as intended; `negative-redaction.log` |
| `make quality` after final source changes | Passed; `verified-quality.log`, 17 Python methods in 53.793 s plus wrapper/process/install suites |
| `KUJO_BIN=kujo bash scripts/benchmark.sh` before and after | Passed; `baseline-benchmark.log`, `final-benchmark.log` |
| `KUJO_BIN=kujo python3 scripts/benchmark-arguments.py --baseline .muzzle/state/audit-2026-10-10/baseline --output docs/audits/2026-10-10-arguments-benchmark.json` | Passed; 36 semantically checked samples including warmups |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Passed; zero diagnostics |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- run tests/muzzle_eval.json --output-dir .muzzle/state/audit-2026-10-10/eval --json` | Passed; 4/4 in 43,996 ms |
| Temporary project: `muzzle init`, copy `examples/build-check/{workflows,manifests}`, `muzzle run build-check --json` | Passed; exact expected no-build-entrypoint log; `example-smoke.log` |
| Temporary project: `MUZZLE_ROOT=<checkout> kujo run <checkout>/muzzle.kujo -- run hello-bash --json --dry-run` | Passed; direct entrypoint JSON preview |
| Python `compile(path.read_text(), str(path), 'exec')` for regression and new benchmark scripts | Passed without bytecode generation |
| `bash .github/scripts/check-kujo-tool-artifacts.sh` and `git diff --check` | Passed; final whole-range artifact guard run after audit commit |

An initial smoke harness expected the wrong example sentence; inspection corrected the harness to the existing exact output, with no product change. An attempted bytecode cleanup shell command was rejected before execution; syntax was then checked without writing bytecode. These are harness/tool events, not baseline or introduced product failures.

No tests were disabled, assertions weakened, timeouts increased, dependencies installed, sibling repositories changed or public release published. Local ignored logs contain full command output; committed benchmark data preserves the portable measurement evidence.

## Strata consolidation

Saved in `Agent Notes`, with repository/branch/commit/test provenance:

- `ddd16377-7202-43b0-94d7-c58c1aca3541`: option ownership prevents accidental approval and destructive preview behavior.
- `c484f3b0-1e36-4d3d-9b65-8a3ddc7bc332`: state confinement applies before policy snapshots and cleanup, extending the prior path-boundary note.
- `1c7d4b5b-0231-4ad0-b3c5-fb0ac87ab97b`: dated session handoff/current-state/timeline, indexing the two contracts and preceding September episode.

Exact-ID and conceptual retrieval passed for all three. Existing delimiter/boundary/history memories were linked rather than copied or deleted. No generic completed-work Capture was created. The handoff is finalized with the audit commit and push receipt after publication to the authorized Git remote.
