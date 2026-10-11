# Muzzle hardening — second pass, 2026-10-10

## Repository and baseline

Repository: `kujolang/muzzle`, branch `main`. Starting SHA: `c554f88429805b9e31dcca91b251467e04811dfc`. Ending implementation SHA: `886fefe9799c2954675bced584b9fe5635448249`; the subsequent documentation commit records this report. This is a continuation of the [same-day comprehensive audit](repository-hardening-2026-10-10.md), not a replacement of its evidence.

Muzzle runs trusted local workflows, preserves full disk evidence, and returns compact human/agent receipts. Runtime dependencies remain Kujo, Bash and Unix utilities; optional runners, OpenSSL signing, Kennel packaging and Eval integration are unchanged. Development tests use Python's standard library. No dependency was added or removed and no sibling repository was modified.

The clean starting checkout passed `make quality`: 17 Python methods, wrapper, process lifecycle, installation, Kujo checks, shell syntax and whitespace. Baseline tests and benchmarks use an immutable `git archive` under `.muzzle/state/audit-pass2/baseline`. Newly added targeted tests then reproduced 32 failing subcases across three methods against that baseline. Final verification passes 20 methods and the existing shell suites.

## Review scope

The first pass inspected entrypoint, modules, runner/helper, policy, manifests, redaction, retention, filesystem confinement, process ownership, installer, schemas, package metadata, examples, CI, agent instructions and output contracts. This continuation traced generic CLI parsing and every cleanup value consumer, persisted loop validation and lifecycle, plus installer/policy/doctor failure boundaries. Existing exported helpers were retained rather than removed without consumer evidence. Broad searches exclude `.dogfood/`, `.muzzle/`, `.kujo_cache/` and `.git/`; targeted evidence reads are separate.

Runtime/resource, token/context, command output, dependencies, concurrency and dead-weight conclusions from the first pass remain applicable. No new model/provider integration or network interface exists in these changes. No dependency advisory scan or managed security-service scan is claimed. The existing concise receipt/full-evidence architecture remains appropriate; no new prompt or token budget is warranted.

## Findings

| ID | Priority | Area | Finding and evidence | Action | Status |
| -- | -- | -- | -- | -- | -- |
| MZ-OCT2-001 | P1 | Data integrity | `clean --workflow --json` interpreted a missing value as workflow `true`, deleting its artifacts; empty values removed the filter entirely. Baseline sentinel tests fail. | Explicit value ownership, reject missing/empty filters before deletion, parse cleanup once. | Fixed |
| MZ-OCT2-002 | P2 | CLI contracts | Generic parsing consumed the workflow after bare `--json`, so `info --json hello-bash` returned usage. | Treat bare JSON flag as boolean; verify command aliases and loop positionals. | Fixed |
| MZ-OCT2-003 | P2 | State | Structurally valid but unreachable loop progress, premature completion, invalid workflow identity and excessive limits were accepted. | Validate persisted state against supported lifecycle invariants. | Fixed |
| MZ-SEP-009 | P1 | Concurrency | Previously reproduced simultaneous starts can create multiple active loops. State validation does not serialize writers. | Preserve explicit single-writer requirement and existing tracking. | Open |

## Changes implemented

### Cleanup values and JSON positionals

Root cause: a generic boolean/value heuristic treated a missing cleanup value as `true`, while an empty string also represented the absence of a workflow filter. `src/cli.kujo` now exposes `parse_command_args`, preserving the existing helper exports and adding missing-value metadata. `muzzle.kujo` consumes one parsed cleanup result, distinguishes omitted from empty filters, and returns `OPTION_VALUE_REQUIRED` or `WORKFLOW_NAME_INVALID` before deletion. Numeric/range validation remains intact. Bare `--json` cannot consume a positional argument.

Tests: `test_cleanup_missing_values_never_select_artifacts` preserves a workflow-true sentinel across six invalid invocations and checks a valid equals-form preview. `test_json_inspection_flag_preserves_positionals` compares eight inspection aliases with both flag orders and exercises loop start/next/done/status. Documentation: agent guide and changelog. CLI compatibility: valid ordinary invocations and JSON schemas remain unchanged; ambiguous missing/empty values now exit 2. A workflow literally named `-n` must use `--workflow=-n`, as documented, to distinguish it from preview. Existing invalid nonempty names retain their prior error exit.

### Reachable loop state

Root cause: validation checked scalar types and individual entry order but did not relate entry count, progress and completion. `src/loops.kujo` requires a valid workflow name, limit 1..1000, zero or one open iteration, and complete accounting at completion. `test_loop_rejects_unreachable_state_without_mutation` tests four corruptions through status, next, summary and done, checks byte-preserving failure, and verifies a full valid three-iteration lifecycle. Security documentation describes the boundary. Valid state generated by supported commands remains compatible; malformed manually edited state receives `LOOP_STATE_INVALID` without mutation. Atomic writes remain; writer coordination is still unresolved.

## Performance and efficiency

Same local Darwin x86_64 / Kujo 1.5.0 benchmark, five startup samples and 50,000 output lines:

| Signal | Baseline | Final |
| -- | --: | --: |
| Startup average | 130 ms | 169 ms |
| Full log bytes | 4,000,000 | 4,000,000 |
| JSON receipt bytes | 531 | 531 |
| Peak RSS bytes | 25,366,528 | 25,137,152 |
| Five concurrent workflows | 1,154 ms | 1,302 ms |

These are noisy, unpaired host-local observations, not evidence of speedup or a causal regression. No performance optimization is claimed. Cleanup now reuses one parse by source inspection, but its timing was not isolated. No tokenizer measurement or token-saving claim; bytes are not tokens. Dependencies and build outputs are unchanged. Full raw logs remain operator-retained; no evidence was truncated. Previous paired argument benchmark remains in the first report and is not attributed to this second pass.

## Security and compatibility

Reviewed trust boundaries include option ownership before deletion, persisted state before mutation, workflow names, existing canonical path confinement, trusted scripts and policy inputs. New tests prevent ambiguous destructive selection and prove malformed-state rejection preserves evidence. Same-user mutation and arbitrary trusted workflow code are not sandboxed. No security control, assertion or timeout was weakened.

Public APIs: existing exports unchanged, one additive parser export. CLI: error handling and boolean positionals corrected as described above. File formats, JSON schemas, config and environment variables: unchanged. External consumers of valid commands remain supported; callers relying on empty filters or malformed states must correct their inputs. No new minimum runtime requirement. Linux and the exact CI-pinned runtime were not executed locally; existing CI matrix remains the cross-platform gate.

## Cross-repository follow-ups and remaining work

No cross-repository change is required for these fixes. P1: loop writer coordination remains tracked in existing SignalBox Capture `cap_07e49865-0784-4f4f-9727-7bbf8b5b610b` and Signal `sig_649f835d-2ac5-4368-8c9c-a396a1d569e0`. Adoption of newer Kujo file-lock APIs would require an explicit minimum-runtime/CI-pin decision; the existing pin lacks those APIs. Do not infer that stricter state validation resolves this race.

P0: none established. P2 / needs more evidence: cross-platform performance and exceptional long-line resource usage, as recorded previously. P3: no cosmetic rewrite. Not worth changing without evidence: historical artifacts, compatibility helper exports or the full-log/compact-receipt contract. No new unresolved high-signal finding was admitted: SignalBox: no captures warranted.

## Verification receipt

Exact commands from the repository root; verbose logs are ignored local artifacts in `.muzzle/logs/audit-pass2/`.

| Command | Result |
| -- | -- |
| `make quality` before edits | Pass, 17 Python methods plus shell suites/checks |
| `KUJO_BIN=kujo MUZZLE_TEST_ROOT="$PWD/.muzzle/state/audit-pass2/baseline" python3 tests/muzzle_hardening_regression.py HardeningTests.test_cleanup_missing_values_never_select_artifacts HardeningTests.test_json_inspection_flag_preserves_positionals HardeningTests.test_loop_rejects_unreachable_state_without_mutation` | Expected failure: 32 subcases, 3 methods |
| `KUJO_BIN=kujo python3 tests/muzzle_hardening_regression.py HardeningTests.test_cleanup_missing_values_never_select_artifacts HardeningTests.test_json_inspection_flag_preserves_positionals HardeningTests.test_loop_rejects_unreachable_state_without_mutation` | Pass, 3 methods |
| `make quality` after edits | Pass, 20 methods in 55.988 s; wrapper/process/install suites, Kujo checks, shell syntax, whitespace |
| `KUJO_BIN=kujo bash .muzzle/state/audit-pass2/baseline/scripts/benchmark.sh` | Pass; baseline signals above |
| `KUJO_BIN=kujo bash scripts/benchmark.sh` | Pass; final signals above |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- lint tests/muzzle_eval.json` | Pass |
| `KUJO_ISOLATED_IMPORTS=1 kujo run ../eval/main.kujo -- run tests/muzzle_eval.json --output-dir .muzzle/state/audit-pass2/eval --json` | Pass, 4/4 |
| `bash .github/scripts/check-kujo-tool-artifacts.sh` | Pass |
| `git diff --check` | Pass |

The new behavioral tests run under the existing `make quality` CI ratchet; no timing thresholds added. No newly introduced regression remains known.

## Durable record

Strata contract `ddd16377-7202-43b0-94d7-c58c1aca3541` was merged with the cleanup/JSON ownership correction; new reachable-loop contract `1176bf83-0909-4243-b1a4-8b124e2b21fd` links earlier state and concurrency evidence. Both passed exact-ID and conceptual retrieval. The October handoff is updated after push with the final commit and this report, preserving the earlier timeline. Completed changes and normal checks were rejected from SignalBox capture; the pre-existing loop item remains the follow-up.
