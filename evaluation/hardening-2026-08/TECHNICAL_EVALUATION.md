# Muzzle Before/After Hardening Evaluation

Evaluation date: 2026-08-30  
Baseline: `75c2e1d20ed060b22df01c44d28221cd672a02fa`  
Current: `55c149271e3c6b81b993879d5bdd7f79e96a0cca` (`v1.1.0`)

## Executive Summary

The dedicated hardening pass made Muzzle materially safer and more deterministic, but not faster or leaner. The strongest independent result is the matched Kujo Eval suite: the baseline passed 2 of 11 outcome checks (18%), while current passed 11 of 11 (100%). Both versions completed a normal workflow and retained raw evidence. Current additionally proved owner-only artifact permissions, versioned run-result routing, forced-installer symlink refusal, workflow validation/execution byte binding, and signed-policy verification/parsing byte binding. The same externally controlled race workloads caused the baseline to execute replaced workflow bytes and accept policy bytes that were not signed; current denied both with exit 3.

Those gains have a measurable cost. Across ten paired end-to-end samples after three warmups, a typical 100-line workflow moved from a median 825.6 ms to 1,314.6 ms: +489.0 ms, or 59.2%. Current was slower in all 10 paired samples. A 50,000-line agent-facing workload moved from 3,850.4 ms to 4,588.5 ms: +738.2 ms, or 19.2%, also slower in all 10 pairs. The change is primarily system time: typical-workload median system CPU rose from 120 ms to 370 ms, consistent with construction, linking, copying, hashing, permission changes, and cleanup of the private execution snapshot. The first six end-to-end workloads were measured while one-minute host load remained between 9.8 and 17.9; alternating AB/BA order reduced drift bias. Later failure and script-size workloads encountered unrelated host load as high as 129.3 and are retained, but receive lower confidence.

Agent-visible output did not become smaller. The same 100-line run preserved the same 7,500-byte log, but the JSON receipt grew from 462 to 512 bytes (+50 bytes, +10.8%) because `schema_version` and `command` were added. The 50,000-line workload retained the same 3,750,000-byte log and grew from 470 to 519 agent-visible bytes (+49 bytes, +10.4%). This remains excellent compression relative to direct output—more than 99.98% by bytes—but that compression already existed at the selected baseline. The hardening pass slightly regressed context payload size in exchange for an explicit automation contract. Exact LLM token savings and dollar costs are **not demonstrated**: no model/provider run, provider usage receipt, or compatible tokenizer was available. Bytes and lines are reported instead.

Memory was effectively neutral for normal output workloads: typical peak RSS median rose 1.0% and the large-output case rose 0.05%, both smaller than a meaningful portable claim. The 16 MiB script workload showed a 32.5% median RSS increase (42,690,560 to 56,547,328 bytes), but it ran during severe unrelated contention; treat this as a credible regression signal that needs clean-host confirmation, not a release-grade magnitude. No package dependency was added. The declared Kujo minimum was corrected from 0.1.0 to 1.0.0. Installed bytes rose from 114,356 to 123,914 (+9,558, +8.4%) and installed files from 17 to 18, mainly from the new run-result schema and hardening code.

The implementation became more complex rather than being cleaned down: source nonblank LOC rose from 3,249 to 3,429 (+180, +5.5%), control-flow keyword count from 592 to 623 (+31, +5.2%), and function definitions from 108 to 112. Test nonblank LOC rose 141 lines (+13.1%). This is mostly explicit security machinery and regression coverage, not hidden deletion or dependency relocation. Both versions passed their native `make quality` gates with the same Kujo 1.1.0 release binary. Current also passed every new matched outcome check.

For users, v1.1.0 is a stronger trusted-local boundary: secrets in Muzzle-owned artifacts are no longer exposed through a permissive umask, validated scripts are the bytes actually executed, signed policy bytes are the bytes parsed, unsafe forced installation layouts fail closed, and JSON consumers can route on a stable discriminator. Users also pay roughly half a second of additional fixed latency for ordinary Bash workflows on this machine, more system CPU, a small JSON payload increase, and a larger installed/source footprint. This is a security/reliability hardening success, not a performance optimization success.

## Before/After Scorecard

| Metric | Baseline | Current | Change | Classification |
|---|---:|---:|---:|---|
| Kujo Eval matched outcomes | 2/11 (18%) | 11/11 (100%) | +9 passes | **Clear improvement — Measured** |
| Typical 100-line median wall time | 825.6 ms | 1,314.6 ms | +489.0 ms, +59.2% | **Regression — Measured** |
| Typical p95 wall time | 877.4 ms | 1,513.0 ms | +635.6 ms, +72.4% | **Regression — Measured** |
| Large 50,000-line median wall time | 3,850.4 ms | 4,588.5 ms | +738.2 ms, +19.2% | **Regression — Measured** |
| Large-output throughput | 12,985.7 lines/s | 10,896.7 lines/s | -2,089.0 lines/s, -16.1% | **Regression — Derived** |
| Typical median peak RSS | 24,743,936 B | 24,983,552 B | +239,616 B, +1.0% | **Neutral/inconclusive — Measured** |
| 16 MiB-script median peak RSS | 42,690,560 B | 56,547,328 B | +13,856,768 B, +32.5% | **Likely regression; high-load confirmation needed — Measured** |
| Typical JSON receipt | 462 B, 1 line | 512 B, 1 line | +50 B, +10.8% | **Intentional tradeoff — Measured** |
| 50,000-line full evidence log | 3,750,000 B | 3,750,000 B | 0 | **Neutral; evidence preserved — Measured** |
| Muzzle-owned artifact mode | `0644` | `0600` | owner-only | **Clear improvement — Measured** |
| Workflow replacement race | mutated bytes executed, exit 0 | denied, exit 3 | fail-closed | **Clear improvement — Measured** |
| Signed-policy replacement race | unsigned replacement authorized, exit 0 | denied, exit 3 | fail-closed | **Clear improvement — Measured** |
| Forced installer symlink | wrote through link, exit 0 | denied, exit 3 | fail-closed | **Clear improvement — Measured** |
| Source nonblank LOC | 3,249 | 3,429 | +180, +5.5% | **Complexity cost — Measured** |
| Test nonblank LOC | 1,074 | 1,215 | +141, +13.1% | **Coverage investment — Measured** |
| Installed footprint | 114,356 B / 17 files | 123,914 B / 18 files | +9,558 B, +8.4% | **Regression/tradeoff — Measured** |
| Direct package dependencies | 0 | 0 | 0 | **Neutral — Measured** |
| Exact LLM tokens/cost | not measured | not measured | not demonstrated | **Not demonstrated** |
| Compiled binary/build time | not applicable | not applicable | script/Kujo project | **Not applicable** |

## Evaluation Boundary

### Current

- Branch at evaluation start: `main`, tracking `origin/main`.
- SHA: `55c149271e3c6b81b993879d5bdd7f79e96a0cca`.
- Commit time: 2026-08-30T19:28:33-04:00.
- Tag: `v1.1.0`.
- Worktree at evaluation start: clean.

### Baseline selection

The selected baseline is `75c2e1d20ed060b22df01c44d28221cd672a02fa`, committed 2026-08-23T16:48:40-04:00. This is not an inferred favorable point: `docs/audits/repository-hardening.md` explicitly records it as the starting SHA of the dedicated hardening audit. It is the direct parent of the five-commit hardening/release series.

The reasonable alternative is tag `v1.0.0` at `f59db6dea559d3216dfe0ab41645c15ed5e16064`. It was rejected because 14 additional commits—3,086 insertions and 382 deletions—separate `v1.0.0` from the dedicated audit start. Using that tag would blend earlier lifecycle, manifest, redaction, concurrency, policy, installation, benchmark, and readability work into this evaluation and would exaggerate the apparent scope of the pass.

## What Changed and Why

### Private artifacts

**Observed code change:** logs are pre-created under umask `077`; Markdown and JSON reports use a private-write runtime primitive and verify mode `0600`.

**Previous problem:** raw logs deliberately retain unredacted evidence, yet baseline inherited the caller's `022` umask and produced `0644` files.

**Expected metric:** artifact confidentiality and failure reliability; minimal runtime/system-call overhead.

**Measured result:** baseline produced `0644` for log, Markdown, and JSON artifacts. Current produced `0600` for all three. This outcome accounts for one Eval pass gained.

### Signed-policy byte binding

**Observed code change:** current reads the policy once, writes an owner-only verification snapshot, asks OpenSSL to verify that snapshot, deletes it, and parses the original in-memory byte string.

**Previous problem:** baseline verified a caller-controlled pathname and later reopened it for parsing. A local replacement between those operations could authorize bytes OpenSSL never verified.

**Expected metric:** deterministic authorization and race resistance; additional file I/O.

**Measured result:** an instrumented OpenSSL wrapper replaced the source bundle immediately after successful signature verification. Baseline parsed the replacement and ran the denied workflow with exit 0. Current parsed the originally read bytes and denied with exit 3. This accounts for two Eval assertions and directly demonstrates the behavioral consequence.

### Workflow validation/execution byte binding

**Observed code change:** current passes the validated digest to the Bash helper, creates a private shadow project, symlinks sibling entries for compatibility, copies the selected script, re-hashes it, executes the snapshot, and cleans it on normal and interrupted paths.

**Previous problem:** baseline validated and hashed one pathname read, then the selected interpreter reopened that mutable pathname.

**Expected metric:** deterministic execution and replacement-race resistance, with additional process, filesystem, hashing, and cleanup cost proportional to directory entries plus script bytes.

**Measured result:** a common external helper barrier replaced the source after validation but before helper execution. Baseline executed `mutated-bytes` and exited 0. Current detected the digest mismatch, logged a controlled denial, and exited 3. End-to-end paired latency rose by about 0.45–0.74 seconds across output workloads; median system CPU rose 250 ms for the typical case and 330 ms for the 50,000-line case. Current was slower in every paired success sample. This is the primary cause of the runtime graph moving.

### Installer and CI supply chain

**Observed code change:** the installer rejects symlinked/non-directory managed roots; CI checks out Kujo at full SHA `b8a44653ad9c225e3d31d96c5c1a0d61f9c8d835`.

**Previous problem:** forced installation followed a pre-existing symlink, and CI executed a mutable external default branch.

**Measured result:** baseline populated the external symlink target (the sorted path listing was 1,238 bytes) and exited 0. Current created no external files and exited 3. CI pinning is statically observed and auditable; this local evaluation did not simulate upstream branch mutation.

### Versioned run-result contract

**Observed code change:** run JSON gains `schema_version: muzzle.run/v1` and `command: run`, plus a strict schema file.

**Previous problem:** the documented versioned automation contract lacked a discriminator.

**Measured result:** baseline failed both discriminator checks; current passed. The cost is fixed at 49–50 bytes in measured receipts, depending on path-length variation. Full evidence size and one-line output shape are unchanged.

### Documentation and dependency contract

Documentation was aligned with effective cleanup, artifact, lifecycle, and JSON behavior. The declared Kujo minimum moved from 0.1.0 to 1.0.0. No package dependency was added. These are observed contract corrections; no runtime speed benefit is claimed.

## Benchmark Methodology

### Environment

- macOS 26.3.1 (Darwin 25.3.0), x86_64.
- Intel Core i7-9750H, 6 physical / 12 logical cores.
- 16 GiB RAM, APFS.
- Fixed Kujo release binary: 1.1.0, SHA-256 `3cf109a03bcf40737a6ce22bdebd8c1c5395733418705fd103356fb8a7043d0a`.
- Rust/Cargo 1.96.0, Bash 3.2.57, Node 24.20.0, Python 3.10.5, OpenSSL 3.6.3.
- `LC_ALL=C`, `LANG=C`, `TZ=UTC`; same Kujo module path and workflow inputs for both versions.

### Design

Each revision ran in a detached worktree. Each label used an isolated initialized project. For every workload the harness performed three warmups, then 10 measured runs (15 for startup). Order alternated baseline/current then current/baseline so each sample pair remained adjacent under changing machine load. `/usr/bin/time -l` supplied user CPU, system CPU, and peak RSS; monotonic high-resolution time supplied wall latency. The harness retained stdout bytes/lines, report metadata, artifact modes, log bytes, exit code, and one-minute load for every sample.

Workloads were identical:

- Minimal: version startup and a 10-line Bash workflow.
- Typical: 100 output lines.
- Scaling/large: 1,000, 10,000, and 50,000 output lines.
- Stress/agent-facing: 50,000 lines retained in the raw log while only JSON enters active context.
- Failure: 5,000 lines followed by exit 7.
- Script scaling: valid 1 KiB, 64 KiB, 1 MiB, 4 MiB, and 16 MiB Bash scripts with constant useful output.

Median is the primary statistic. Sample standard deviation is reported. p95 and p99 are observed order statistics; at `n=10`, both equal the maximum and are not a stable population estimate. Raw results preserve min, max, mean, median, p95, p99, standard deviation, sample count, and pair order.

### Load limitation

Startup and output workloads ran at median one-minute loads of 10.1–15.9, with within-workload maxima no higher than 17.9. The host has 12 logical cores and was busy, but the adjacent alternating pairs were stable enough to identify a consistent fixed-cost regression: current was slower in 49 of 50 output-workload pairs (and 11 of 15 startup pairs).

Unrelated work later raised load substantially. Failure samples saw load 31.4–62.2; script-scaling samples saw 44.4–129.3. Those raw samples are preserved rather than discarded, but their absolute values and memory magnitudes have lower confidence. The separately isolated helper diagnostic was run under load 538.7–799.6 and is retained only as root-cause direction, not as a portable performance result.

## Runtime Results

| Workload | n | Baseline median | Current median | Change | Baseline p95 | Current p95 | Paired current-slower |
|---|---:|---:|---:|---:|---:|---:|---:|
| Startup | 15 | 208.8 ms | 227.0 ms | +18.2 ms (+8.7%) | 235.2 | 253.3 | 11/15 |
| Output 10 | 10 | 760.2 ms | 1,222.5 ms | +462.3 ms (+60.8%) | 1,073.1 | 1,686.9 | 10/10 |
| Output 100 | 10 | 825.6 ms | 1,314.6 ms | +489.0 ms (+59.2%) | 877.4 | 1,513.0 | 10/10 |
| Output 1,000 | 10 | 907.1 ms | 1,387.6 ms | +480.5 ms (+53.0%) | 1,380.7 | 1,536.9 | 9/10 |
| Output 10,000 | 10 | 1,668.2 ms | 2,178.3 ms | +510.0 ms (+30.6%) | 1,885.0 | 2,925.4 | 10/10 |
| Output 50,000 | 10 | 3,850.4 ms | 4,588.5 ms | +738.2 ms (+19.2%) | 4,222.3 | 5,311.9 | 10/10 |
| Failure 5,000 | 10 | 5,857.8 ms | 6,378.0 ms | +520.1 ms (+8.9%) | 7,454.2 | 7,116.1 | 7/10 |

The output workloads show an approximately fixed 0.45–0.51 second snapshot/setup cost through 10,000 lines, after which script execution dominates. The percentage penalty therefore falls as useful work grows. At 50,000 lines, paired median difference was 726.1 ms and paired standard deviation 360.3 ms. The direction is unambiguous; the exact magnitude is host-specific.

Representative full distributions (milliseconds):

| Workload/version | min | max | mean | median | stddev |
|---|---:|---:|---:|---:|---:|
| Typical baseline | 763.8 | 877.4 | 824.5 | 825.6 | 31.8 |
| Typical current | 1,240.5 | 1,513.0 | 1,340.3 | 1,314.6 | 93.1 |
| Large baseline | 3,479.4 | 4,222.3 | 3,843.2 | 3,850.4 | 235.4 |
| Large current | 3,949.7 | 5,311.9 | 4,588.9 | 4,588.5 | 435.0 |
| Failure baseline | 4,304.7 | 7,454.2 | 5,876.4 | 5,857.8 | 944.5 |
| Failure current | 5,326.1 | 7,116.1 | 6,236.1 | 6,378.0 | 674.0 |

### CPU and memory

Typical user CPU median rose 630 to 800 ms (+27.0%); system CPU rose 120 to 370 ms (+208.3%). Large-output user CPU rose 2,600 to 2,760 ms (+6.2%); system CPU rose 1,025 to 1,355 ms (+32.2%). This supports the filesystem/process snapshot mechanism as the causal cost rather than the workflow body.

Typical peak RSS was 24,743,936 versus 24,983,552 bytes (+1.0%). Large-output RSS was 25,919,488 versus 25,931,776 bytes (+0.05%). These are neutral within host noise. The high-load 16 MiB script signal was 42,690,560 versus 56,547,328 bytes (+32.5%); confirm on an idle release runner before setting a memory gate.

## Scaling Analysis

Output scaling remains broadly linear in emitted lines for both versions. The hardening mostly adds a fixed setup term, so its percentage impact shrinks as workflow work increases: +60.8% at 10 lines, +59.2% at 100, +53.0% at 1,000, +30.6% at 10,000, and +19.2% at 50,000. There is no evidence of quadratic or runaway output capture: full log bytes were exactly identical between versions at every output size, and agent-facing stdout remained one line.

Script-size scaling samples were contaminated by later host load, but current was slower in all 50 pairs. Median changes were +50.0% at 1 KiB, +63.6% at 64 KiB, +50.0% at 1 MiB, +42.8% at 4 MiB, and +26.9% at 16 MiB. Absolute paired differences stayed roughly 0.70–0.85 seconds rather than exploding with size on the tested range. That supports a large fixed directory/process setup cost plus a smaller linear copy/hash term, not pathological scaling.

## Token, Context, and Agent Efficiency

No LLM was invoked by Muzzle and no provider usage record exists. Exact input, output, cached, prompt, completion, and total token counts are therefore **not demonstrated**. Applying an arbitrary characters-per-token ratio would violate the evaluation rules.

Exact context-facing bytes provide a model-independent measure:

| Workload | Raw evidence | Baseline active output | Current active output | Current vs baseline |
|---|---:|---:|---:|---:|
| 10 lines | 750 B | 459 B / 1 line | 509 B / 1 line | +50 B (+10.9%) |
| 100 lines | 7,500 B | 462 B / 1 line | 512 B / 1 line | +50 B (+10.8%) |
| 50,000 lines | 3,750,000 B | 470 B / 1 line | 519 B / 1 line | +49 B (+10.4%) |
| Failure, 5,000 lines | 375,000 B | 845 B / 1 line | 895 B / 1 line | +50 B (+5.9%) |

Current still removes 99.986% of the 50,000-line raw bytes from active output while retaining all evidence on disk. Baseline removed 99.987%. The hardening pass did not create this efficiency and slightly reduced it via the schema fields. Task success remained unchanged for normal/failure workloads, and evidence bytes remained exact.

Each workload required one Muzzle tool invocation in both versions. Repeated tool calls, model reasoning/action cycles, retries, provider messages, and real-agent completion rates were not measured. The deterministic outcome suite is an agent-automation proxy, not a substitute for a live model study.

Operational byte overhead from the new contract is about 50 bytes per execution: approximately 5,000 bytes per 100 executions, 50,000 per 1,000, and 500,000 per 10,000. No dollar conversion is made because bytes are not provider tokens and no authoritative local price/model configuration was available.

## Build, Dependency, and Artifact Footprint

Muzzle is a Kujo/Bash source package; it has no repository-local compiled binary or conventional clean/incremental/release build. Binary size and compiler build time are not applicable. The fixed external Kujo binary was identical for both versions.

Direct package dependencies remained zero. Runtime requirements remained Kujo, Bash, optional Python/Node runners, OpenSSL for signed policy, and Git for policy checks. The declared Kujo minimum was corrected from 0.1.0 to 1.0.0; this narrows documented compatibility rather than adding a dependency.

The versioned install footprint rose from 17 files / 114,356 bytes to 18 files / 123,914 bytes: one file and 9,558 bytes (+8.4%). The additional schema and security code explain the growth. Native quality gates passed for each revision with the same Kujo release binary; timing those different-sized test suites would not be a fair build-speed comparison.

## Complexity and Maintainability

| Structural metric | Baseline | Current | Change |
|---|---:|---:|---:|
| Tracked files | 50 | 52 | +2 |
| Tracked bytes | 256,799 | 288,489 | +31,690 (+12.3%) |
| Source files | 16 | 16 | 0 |
| Source nonblank LOC | 3,249 | 3,429 | +180 (+5.5%) |
| Function definitions | 108 | 112 | +4 (+3.7%) |
| Control-flow keywords | 592 | 623 | +31 (+5.2%) |
| Test nonblank LOC | 1,074 | 1,215 | +141 (+13.1%) |
| Documentation nonblank LOC | 1,605 | 1,735 | +130 (+8.1%) |
| TODO/FIXME | 0 | 0 | 0 |

Complexity was added, not removed or merely relocated. Most growth is concentrated in `src/muzzle_exec.sh`, which entered the five largest source files at 179 nonblank lines, plus race/lifecycle tests and the audit. The trade is defensible because the new branches implement explicit security invariants and cleanup paths with outcome tests. Maintainability nonetheless declined in the narrow senses of size, branching, and shell orchestration. The snapshot helper is the primary future simplification target.

## Reliability and Determinism

Both revisions passed their own `make quality` gate with the same fixed Kujo 1.1.0 release binary, including Kujo checks, Bash syntax, whitespace/diff checks, wrapper regressions, process lifecycle regressions, and installer regressions. Current's suite includes additional private-mode, race, identity/import, cleanup, and installer-confinement cases.

The fair cross-version Eval suite used the same 11 checks and evidence-generation workload:

| Eval category | Baseline | Current | Delta |
|---|---:|---:|---:|
| Common workflow/evidence checks | 2/2 | 2/2 | 0 |
| Artifact/installer/byte-binding checks | 0/7 | 7/7 | +7 |
| Automation discriminators | 0/2 | 2/2 | +2 |
| Overall actual checks | 2/11 (18%) | 11/11 (100%) | +9 |

These are actual Kujo Eval check counts, not invented scores. Eval's `summary.json` records baseline `pass_rate: 18`; the generated Markdown report incorrectly renders `0%`, an Eval repository reporting defect documented as a cross-repository follow-up. Current renders 100% correctly.

## Change-to-Result Mapping

| Code change | Behavioral change | Measured impact | Tradeoff |
|---|---|---|---|
| Private log/report creation | Muzzle artifacts no longer inherit permissive umask | `0644` → `0600`; Eval fail → pass | Extra permission/write verification |
| Read-once policy snapshot | Parsed bytes equal verified bytes | replacement authorized/exit 0 → denied/exit 3 | Temporary private file and OpenSSL path change |
| Validated workflow snapshot | Executed bytes equal hashed bytes | mutated bytes executed → digest denial/exit 3 | typical +489.0 ms; system CPU +250 ms |
| Installer path-type checks | `--force` fails closed on managed symlink | external writes → zero external writes; exit 0 → 3 | Unsafe legacy layouts no longer install |
| JSON schema/command fields | Consumers can route and validate results | two Eval failures → two passes | +49–50 active-output bytes |
| CI Kujo SHA pin | reviewed runtime revision is selected | mutable ref removed (observed) | deliberate update work required |
| Kujo minimum 1.0.0 | package contract matches used APIs | stale compatibility claim removed | users below 1.0.0 explicitly unsupported |

## Commit Attribution

| Commit | Change | Intended effect | Observed/measured effect |
|---|---|---|---|
| `1de8e9a` | Private artifacts, policy read binding, installer checks, CI pin, JSON schema | close confidentiality/supply-chain/contract gaps | artifact, policy, installer, and discriminator checks move from fail to pass; +49–50 bytes |
| `e1864a7` | Initial hardening audit | preserve evidence and boundary | provides defensible baseline and prior five-sample signal; no runtime change |
| `5f5d792` | Workflow snapshot, digest verification, cleanup/identity compatibility | bind validated bytes to execution | race moves from mutated execution to denial; dominant ~0.5–0.7 s runtime cost |
| `a513a8d` | Audit closure | document workflow-byte fix | documentation only |
| `55c1492` | Version 1.1.0 release preparation | align package/docs/version | no feature runtime effect beyond longer version string; installed version paths change |

## Regressions and Tradeoffs

| Metric | Baseline | Current | Severity | Likely cause | Assessment/action |
|---|---:|---:|---|---|---|
| Typical median latency | 825.6 ms | 1,314.6 ms | Medium | private snapshot/link/hash/cleanup | Security benefit is real; optimize helper without weakening byte binding |
| Large median latency | 3,850.4 ms | 4,588.5 ms | Medium | same fixed cost plus I/O | Accept for v1.1.0, add release regression budget |
| Typical system CPU | 120 ms | 370 ms | Medium | filesystem/process orchestration | Profile on idle macOS/Linux |
| Agent JSON bytes | 462 | 512 | Low | two stable discriminator fields | Acceptable automation contract tradeoff |
| Installed bytes | 114,356 | 123,914 | Low | schema/security implementation | Acceptable; track rather than remove schema |
| Source/control complexity | 3,249 LOC / 592 branches | 3,429 / 623 | Low–medium | explicit shell security lifecycle | Consolidate snapshot primitive if runtime support permits |
| 16 MiB-script RSS signal | 42.7 MB | 56.5 MB | Medium, low confidence | copy/hash plus high contention | Re-run on clean release runner before threshold |
| Minimum Kujo version | 0.1.0 declared | 1.0.0 declared | Compatibility tradeoff | contract correction | Correct and intentional |

No functionality loss was found in the tested normal, large-output, failure, Bash identity, evidence, installer, and policy paths. The statement “No statistically or operationally meaningful regressions” would be false: runtime, system CPU, active-output bytes, footprint, and complexity all regressed.

## Remaining Opportunities

- **P0:** none identified.
- **P1:** reduce the ~0.5–0.7 second workflow-snapshot setup cost without reopening the pathname race. Profile directory linking, shell launches, duplicate hashing, and cleanup separately; prefer a runtime primitive that opens/copies/verifies once.
- **P1:** add a clean-host macOS/Linux paired benchmark job with load gating and retained raw distributions. Gate typical median/p95, system CPU, and large-script RSS after establishing platform baselines.
- **P2:** replace the shadow-project symlink farm with a smaller compatibility mechanism if Bash/Python/Node identity/import contracts can remain intact.
- **P2 (cross-repository, Eval):** fix Markdown pass-rate rendering for partial success; `summary.json` reports 18 while `eval-report.md` reports 0%.
- **P3:** measure exact provider tokens only in a separately controlled live-agent study with fixed model/provider/parameters and usage receipts. Do not infer them from bytes.

## Known Non-Demonstrated Areas

- Exact LLM tokens, cached tokens, provider cost, prompt/context growth, and model task quality.
- Real-agent reasoning cycles, repeated calls, retry rates, and completion rate.
- Network calls/conditions; tested workflows were local and deterministic.
- Allocation counts and disk read/write bytes; wall/CPU/RSS and artifact bytes were measured instead.
- Stable p99; sample counts support observed maxima, not population-tail claims.
- Cross-platform performance magnitude; correctness is supported by the repository's Ubuntu/macOS CI history, but this benchmark host was macOS x86_64.

## Reproducibility and Evidence

The exact commands are in `README.md`. Raw and derived evidence is retained under `results/`, including all end-to-end samples, load per sample, helper diagnostic samples, capability outputs, Kujo Eval details, native quality logs, structure metrics, install footprint, and the combined `evaluation-results.json`. Large generated workflow logs are reproducible but are not duplicated in Git; their exact measured byte counts and run receipts are retained.

Searches excluded `.dogfood/`, `.muzzle/`, and `.kujo_cache/` as historical/generated material, following repository policy.

## Final Question

> If we erase the commit messages and ignore what the hardening work intended to accomplish, does the empirical evidence independently demonstrate that CURRENT is a better engineered version than BASELINE?

**PARTIALLY.**

Independent outcome evidence shows current is substantially safer and more deterministic: 11/11 matched checks versus 2/11, with concrete fail-closed behavior under three previously exploitable replacement/symlink workloads. But “better engineered” cannot be unqualified because current is slower in nearly every paired workload, uses more system CPU, emits a larger active-context receipt, grows memory under the largest script signal, installs more bytes, and adds source/control complexity. Current is the better security and reliability release; it is not the better performance or minimal-footprint implementation.
