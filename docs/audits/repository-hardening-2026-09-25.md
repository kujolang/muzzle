# Repository hardening — 2026-09-25

## Repository and scope

- Repository: `kujolang/muzzle`; branch: `main`.
- Starting SHA: `e5e031dae4d57bc2102955d3d3dcab62d91440b0`; initially clean.
- Ending implementation SHA: `685e035e2fc8bedfd8942974bd09f1737fc72bac`. The subsequent documentation commit records this audit; its SHA is available from `git log -1 -- docs/audits/repository-hardening-2026-09-25.md`.
- Purpose: trusted-local workflow execution with full disk logs, concise receipts, strict manifests, optional policy/integrity checks, and agent loop state.
- Host: macOS x86_64, Kujo 1.5.0. Production dependencies: Kujo, Bash and Unix utilities; Python/Node are optional workflow runners; OpenSSL is optional for signed policy. Python standard library powers development regression tests and benchmarks. No dependency was added or upgraded.
- Integration contracts: launcher and direct Kujo entrypoint; `kennel.toml` package layout; Eval suite; versioned `muzzle.run/v1`, command/error envelopes, manifests and signed policy; consumers may invoke the CLI through Dispatch/MCP or their own automation. No sibling repository was modified. The added `pad_left` use was checked against the CI-pinned runtime source.

Read the canonical README, agent/howto/workflow/security docs; all production source modules and launcher; wrapper, process, install and Python regression suites; Makefile, both CI workflows, installer/signing scripts, schemas, completions, example, package/spec metadata and prior audit/performance records. Broad searches excluded `.git/`, `.dogfood/`, `.muzzle/`, `.kujo_cache/`; historical evaluation evidence was treated as context, not a current contract. Generated audit evidence lives under ignored `.muzzle/state/audit-2026-09-25/`.

## Baseline

`make quality` passed before production changes: Kujo checks, shell syntax, whitespace checks, wrapper contracts, process lifecycle, installed execution, and six hardening test methods. No baseline failure was observed in that gate. An immutable `git archive` of the starting SHA was retained locally for negative tests and paired benchmarks.

Three new test methods run against that archive produced four failures and one error: `.md` workflow-name report corruption, ignored verbose sink failure, execution despite failed initial log creation, absent helper diagnostic, and cleanup accepting malformed identifiers/directories. Retention selection tests for valid artifacts passed against the original implementation before the unrecognized-file assertions failed. This distinguishes existing bugs from changes introduced here.

Baseline benchmark (`5` startup/concurrent runs, `50,000` log lines): 328 ms average startup, 4,000,000 full-log bytes, 531 JSON-receipt bytes, 29,143,040 peak RSS bytes, and 2,004 ms for five concurrent workflows. These are host-local signals, not service guarantees.

## Findings

| ID | Priority | Area | Finding and evidence | Action | Status |
| --- | --- | --- | --- | --- | --- |
| MZ-0925-01 | P1 | Failure semantics | `PIPESTATUS[0]` ignored a failed `tee`; an injected sink consumed output then failed while Muzzle emitted success. Initial log redirection also continued after failure. | Check initialization and both pipeline statuses; preserve prior workflow failures. | Fixed |
| MZ-0925-02 | P1 | Observability | Helper stderr was discarded in quiet/JSON failure excerpts; an injected sink failure yielded no actionable diagnostic. | Include bounded, redacted helper failures in the existing excerpt. | Fixed |
| MZ-0925-03 | P2 | Artifact contract | Global `.md` replacement changed `release.md.notes.md` into `release.json.notes.json` in its companion JSON filename. Exact-workflow cleanup then missed it. | Derive the companion path by replacing only the final suffix. | Fixed |
| MZ-0925-04 | P1 | Retention performance | Every candidate scanned every artifact. Initial 900-artifact samples took roughly 17–18 seconds with `--keep 5`. | Sort timestamp/name ranks once, then count independently per workflow/type. | Fixed; paired measurements below |
| MZ-0925-05 | P2 | Cleanup boundary | A 32-character nonhex identifier was deleted; an artifact-shaped directory caused a cleanup failure. | Require valid workflow, decimal timestamp, hexadecimal identifier and confined regular file; skip integer overflow. | Fixed |
| MZ-0925-06 | P2 | Agent documentation | Verbose output was described as streaming; troubleshooting recommended hiding stderr and incorrectly required executable Bash scripts. | Align examples and failure guidance with actual execution. | Fixed |
| MZ-SEP-009 | P1 | Loop concurrency | Prior audit reproduced eight active loops from eight parallel starts; source still performs unlocked read/modify/write. | Preserve single-writer documentation and existing SignalBox item. | Existing open issue |

## Changes implemented

### Reliable artifact evidence

`src/muzzle_exec.sh` now exits 74 before executing a workflow if its initial log cannot be opened. In verbose mode it captures both pipeline exit statuses immediately. A failed sink changes a successful workflow result to 74; an already nonzero workflow exit is preserved. The helper emits an explicit incomplete-capture diagnostic.

`muzzle.kujo` incorporates helper stderr into failure excerpts, with the existing redactor applied before selecting the final five lines. Diagnostics exceeding 4,096 characters or marked truncated by the runtime receive an explicit omission marker. Raw verbose display retains its existing semantics. Tests inject failing `tee`/`ln` implementations, exercise nonzero-exit precedence, assert that failed initialization never starts the workflow, and check single-line/multiline secret redaction and oversized diagnostics. No actual full-disk condition was required for deterministic reproduction.

`src/report.kujo` supplies one companion-path helper used by both report writers and CLI output. Tests use a workflow with multiple `.md` substrings, compare disk JSON with stdout, check the Markdown reference, and remove all three artifacts through exact-workflow cleanup. Existing wrongly named historical artifacts are not renamed automatically.

### Retention ranking and guarded selection

`src/retention.kujo` replaces the nested ranking scan with one native string sort using zero-padded nonnegative i64 timestamps followed by the original filename. Descending traversal counts each `(workflow, extension)` group separately. A path set identifies retained artifacts while the original collection order controls output. All ranks are computed before age/workflow filtering, preserving established behavior, including future timestamps. `--keep 0` avoids building the ranking index.

The ranking comparison work is O(n log n) rather than O(n²); this is a source-supported statement about ranking, not a guarantee about runtime collection internals. Additional indexes use O(n) entries and are discarded when cleanup returns. Workflow-name validation is memoized only within one directory collection; its immutable string keys cannot become stale, and the memo is discarded when collection returns. Filename components are split once rather than searched twice character by character. Native timestamp padding replaces a per-character loop. There is no persistent cache. Full artifact receipts are retained for reviewability.

Parsing now rejects nonhex IDs, unsafe workflow names, nondigit/overflow timestamps, and nonregular files. Generated artifacts retain their existing names and eligibility. Tests compare selection to an independent numerical oracle across five workflows (including Unicode/newline names) and three extensions, multiple keep values, ties, timestamp widths, absent/exact filters, maximum i64 timestamp, age selection and unknown files. Tests assert deterministic receipt ordering and actual deletion counts. No public function was removed: the replaced ranking helper was private.

### Documentation and gates

Updated README, workflow exit-code guidance, performance methodology, howto diagnostics and changelog. The existing `make quality`/Linux/macOS CI target automatically runs the added behavioral tests; no flaky timing threshold or new CI dependency was introduced. `scripts/benchmark-retention.py` is an optional stdlib benchmark with matched samples and semantic assertions.

## Performance and efficiency

| Artifacts | Before median (ms) | After median (ms) |
| ---: | ---: | ---: |
| 60 | 577.87 | 767.77 |
| 300 | 2575.38 | 2394.33 |
| 900 | 15445.03 | 7421.85 |

The 900-artifact workload improved from 15.45 s to 7.42 s. The 60-artifact workload costs about 190 ms more with stricter file/name validation and index construction; this is an explicit safety/scaling tradeoff, not an across-the-board speedup. The initial implementation had a larger small-workload penalty, which led to native padding, single-pass filename splitting, and per-collection name validation before these final measurements. No functional assertion or safety check was weakened.

One warmup per checkout/workload and five alternating measured pairs at 60, 300 and 900 log artifacts across three workflow groups, retaining five per group. Each sample verifies exact selection against an independent oracle, zero removals, and unchanged file counts. Raw samples and runtime version are committed in [benchmark data](2026-09-25-retention-benchmark.json). Filesystem and host scheduling affect absolute values; no portable latency threshold is claimed.

Existing benchmark before/after on the same host/runtime (five samples/runs):

| Signal | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Startup average | 328 ms | 266 ms | Small noisy sample; no startup speed claim |
| Full log | 4,000,000 bytes | 4,000,000 bytes | Evidence preserved |
| JSON receipt | 531 bytes | 531 bytes | Success footprint unchanged |
| Peak RSS | 29,143,040 bytes | 30,031,872 bytes | Host-local signal; no memory improvement claim |
| Five concurrent workflows | 2,004 ms | 1,915 ms | Not an isolated causal benchmark |

No tokenizer was run; byte counts are not token counts. No new model/provider calls, tool schemas, eager context loading, dependency trees, or persistent caches were introduced. CLI success receipts and full-log volume remain unchanged. Retention intentionally returns full selected-artifact evidence; the fix accelerates ranking without silently truncating that evidence. No build/binary-size claim applies to this interpreted repository. Snapshot preparation, bounded capture and full-log redaction were reviewed and retained rather than rewritten.

## Security, resources and determinism

Reviewed boundaries: literal subprocess argv; canonical workflow/manifest/artifact paths; checksum-bound private snapshots and sibling imports; inherited workflow environment; optional signed authorization; owner-only artifact creation; cleanup eligibility; secret redaction; helper subprocess capture; timeout/cancellation and descendant termination; session and loop-state writes; installer destinations and shipped scanner; CI dependency pins. Existing regression coverage for shell metacharacters, symlink escapes, checksums, policy tampering, private modes, runtime identity, cancellation and concurrent run artifacts remains in force.

This pass fixes evidence integrity and cleanup correctness; it does not claim sandbox isolation or a newly proven privilege-escalation vulnerability. Logs remain sensitive, retention is operator-controlled, and same-user hostile mutation is outside the documented threat model. The awk scanner retains bounded excerpt state but can allocate memory proportional to the longest physical input line. Signed policy issuer/expiry enforcement remains operator-owned as documented. No new network path exists.

Resources remain bounded at process-capture boundaries. Retention materializes artifact metadata and the selected receipt; the additional temporary ranking index is linear in recognized entries. Existing session bookkeeping is best-effort, and its lock is distinct from loop coordination. Loop commands continue to require one writer. Atomic replacement alone cannot serialize transitions.

## Compatibility

- Public APIs: existing exports retained; one report-path helper added.
- CLI: commands, aliases and options unchanged. Successful results retain their fields, types, filenames and exit semantics. Logging infrastructure failures now fail explicitly with 74 when no workflow failure takes precedence; incomplete logs can no longer be represented as successful capture in the tested cases.
- File formats and schemas: unchanged. `.md` inside a workflow name is preserved in the JSON companion filename; prior accidental renaming is not a supported contract.
- Configuration/environment: unchanged; no production variable or runtime minimum bump.
- Cleanup: generated artifacts remain compatible; malformed lookalikes/directories are now counted as unrecognized. No migration is required.
- External consumers: no ecosystem rewrite required. Consumers must tolerate normal nonzero infrastructure failures and should derive JSON companions by replacing the final extension only.

## Cross-repository follow-ups

No sibling change is required for these fixes. The existing loop-lock design question remains: CI pins Kujo `b8a44653ad9c225e3d31d96c5c1a0d61f9c8d835`, which predates newer `file_lock`/`file_unlock` APIs. Adopting them requires a deliberate runtime requirement/CI-pin migration, or a separately verified compatible lock design. Do not hide that compatibility change in cleanup work. This pass ran locally on Kujo 1.5.0; it did not build or claim execution on the pinned runtime or Linux.

The optional Eval adapter is read-only integration with the sibling Eval repository, using `KUJO_ISOLATED_IMPORTS=1` to avoid colliding `src.*` module names.

## Remaining work

- P0: none established in this pass.
- P1: existing MZ-SEP-009 loop-writer coordination, tracked in SignalBox Capture `cap_07e49865-0784-4f4f-9727-7bbf8b5b610b` / Signal `sig_649f835d-2ac5-4368-8c9c-a396a1d569e0`. Source and existing exact Signal retrieval confirmed; no duplicate was created.
- P2 / needs more evidence: matched Linux/pinned-runtime measurements and extremely long awk records. Current tests do not prove behavior under real disk exhaustion or filesystem hardware failure.
- P3: no cosmetic restructuring pursued.
- Not worth changing without evidence: historical evaluation artifacts, compatibility exports, trusted-local environment inheritance, retained full evidence, and the large command-dispatch module solely for line count.

SignalBox: no captures warranted. The existing concurrency item was deduplicated by concept search and exact Signal ID; completed fixes and routine verification were rejected from capture. Strata saved logging contract `1a9f3635-6a73-481b-8151-23c1812c9313` and retention contract `48191a9c-b9fe-4860-9f98-cdf075a34b8d` in Agent Notes; exact-ID and conceptual retrieval both passed. The post-push handoff records the final SHA/timeline and indexes these notes. No duplicate atomic claim or new loop-concurrency finding was saved.

## Verification receipt

Commands run from the Muzzle repository root unless stated otherwise. Log filenames below are under `.muzzle/state/audit-2026-09-25/`.

| Exact command/check | Result/evidence |
| --- | --- |
| `make quality` before changes | Passed; `baseline-quality.log`, six original Python methods |
| `KUJO_BIN=kujo MUZZLE_BENCH_ITERATIONS=5 MUZZLE_BENCH_LINES=50000 bash scripts/benchmark.sh` before and after | Passed; `baseline-benchmark.log`, `final-benchmark.log` |
| `MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-2026-09-25/baseline-repo" KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_report_suffix_preserves_workflow_name HardeningTests.test_log_capture_failure_is_not_success HardeningTests.test_retention_ranking_and_unrecognized_files` | Expected failure on original code; `new-tests-baseline.log`, four failures and one error |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_report_suffix_preserves_workflow_name HardeningTests.test_log_capture_failure_is_not_success` | Passed; `targeted.log` |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_retention_ranking_and_unrecognized_files` | Passed before and after refinement, including Unicode/newline filenames; `retention-tests.log`, `retention-final-tests.log`, `retention-unicode-tests.log` |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py` | Passed; `hardening-tests.log` (nine methods before the dedicated helper-diagnostic method was added) |
| `make quality` after initial implementation | Passed; `final-quality.log`, ten Python methods plus wrapper/process/install suites |
| `make quality` after final retention refinement | Passed; `final-refined-quality.log`, ten Python methods in 69.338 s plus wrapper/process/install suites |
| `kujo check src/retention.kujo` | Passed, also included in the full gate |
| `python3 -m py_compile scripts/benchmark-retention.py tests/muzzle_hardening_regression.py` | Passed; generated bytecode removed afterward |
| `KUJO_BIN=kujo python3 scripts/benchmark-retention.py --baseline .muzzle/state/audit-2026-09-25/baseline-repo --candidate .muzzle/state/audit-2026-09-25/baseline-repo --samples 1 --sizes 60 300 900 --output .muzzle/state/audit-2026-09-25/retention-baseline.json` | Passed; pre-optimization characterization |
| `KUJO_BIN=kujo python3 scripts/benchmark-retention.py --baseline .muzzle/state/audit-2026-09-25/baseline-repo --output docs/audits/2026-09-25-retention-benchmark.json` | Passed; final paired comparison, all selection/preservation assertions; `retention-comparison-final.log` |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Passed; zero diagnostics |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- run tests/muzzle_eval.json --output-dir .muzzle/state/audit-2026-09-25/eval --json` | Passed; 4/4, 84,775 ms; includes wrapper regression |
| Temporary initialized project: copy `examples/build-check/{manifests,workflows}`; `muzzle run build-check --json` | Passed; Python subprocess harness asserted success, empty stderr and exact no-build-system log |
| `bash .github/scripts/check-kujo-tool-artifacts.sh` | Passed |
| `git diff --check` | Passed |

No tests were disabled, no assertions weakened, and no timeouts increased. The optional Eval suite passed without changing its 90-second wrapper check. Local refinement probes are retained as diagnostic evidence, not substituted for the final paired dataset.

Verbose logs, negative-test output, baseline archive and local benchmark signals are retained under `.muzzle/state/audit-2026-09-25/`. Committed paired data is the portable performance evidence; temporary project paths and generated runtime output are not committed.
