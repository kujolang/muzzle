# Hardening Muzzle

## Why we did it

Muzzle keeps noisy workflow output out of active AI-agent context while preserving the full evidence on disk. That makes its trust boundaries important: the receipt must describe the bytes that actually ran, signed policy must authorize the bytes actually parsed, and raw logs must not become broadly readable by accident.

We evaluated the dedicated hardening series from `75c2e1d` to Muzzle `v1.1.0` at `55c1492`. The baseline was the starting SHA recorded by the repository's own audit, not an older release selected for a larger improvement.

## What changed

The release added five concrete protections:

- Muzzle-owned logs and reports are created owner-only.
- Signed policy is read once, verified from a private snapshot, and parsed from those same bytes.
- Workflows execute from a private snapshot whose digest must match the validated source.
- Forced installation rejects symlinked managed roots.
- Run JSON includes stable `muzzle.run/v1` and `command: run` discriminators.

CI also pins the Kujo runtime to a reviewed full commit SHA, and the package now declares the Kujo 1.0.0 minimum it actually requires.

## How we measured it

Both revisions ran identical workloads from detached worktrees with the same Kujo 1.1.0 release binary. End-to-end tests alternated baseline/current order, used three warmups, and collected at least 10 measured samples. A common external harness controlled workflow and policy replacement races. Kujo Eval scored the resulting evidence with one unchanged 11-check suite.

The workloads covered startup, 10/100/1,000/10,000/50,000 output lines, a noisy failure, and script sizes from 1 KiB to 16 MiB. Raw results include wall time, CPU time, RSS, output bytes, evidence bytes, exit status, and host load for every sample.

## Before vs After

| Metric | Before | After | Change |
|---|---:|---:|---:|
| Matched Eval outcomes | 2/11 | 11/11 | +9 passes |
| Typical 100-line median | 825.6 ms | 1,314.6 ms | +489.0 ms (+59.2%) |
| Large 50,000-line median | 3,850.4 ms | 4,588.5 ms | +738.2 ms (+19.2%) |
| Typical peak RSS | 24.74 MB | 24.98 MB | +1.0%, neutral |
| Agent-visible typical JSON | 462 B | 512 B | +50 B (+10.8%) |
| 50,000-line full evidence | 3.75 MB | 3.75 MB | unchanged |
| Artifact mode | `0644` | `0600` | owner-only |
| Installed footprint | 114,356 B | 123,914 B | +8.4% |
| Direct package dependencies | 0 | 0 | unchanged |

## Biggest improvements

The strongest result is behavioral, not cosmetic. Under a controlled post-validation source replacement, baseline executed `mutated-bytes` and exited successfully. Current detected the digest mismatch and denied execution with exit 3. Under a controlled policy replacement after successful OpenSSL verification, baseline authorized the unsigned replacement; current denied it. A forced installer symlink wrote outside the managed root on baseline and wrote nothing on current.

Those changes moved the matched Kujo Eval score from 2/11 to 11/11. Normal workflow completion and raw-evidence retention passed in both versions; all nine gained checks correspond to new security or automation guarantees.

## What surprised us

The security cost is large for short workflows. Current was slower in all 10 paired typical samples. Median system CPU rose from 120 to 370 ms, pointing to snapshot filesystem/process work rather than the workflow itself. The absolute penalty stayed roughly fixed as output grew, so the percentage fell from about 59% for 100 lines to 19% for 50,000 lines.

Muzzle's context compression remained excellent but did not improve in this pass. For 50,000 lines, both versions retained the full 3,750,000-byte log while returning one JSON line. Current returned 519 bytes instead of 470 because the receipt is now explicitly versioned. That is a useful contract tradeoff, not a token-saving result.

## What did not improve

Runtime, system CPU, active-output bytes, source size, control-flow count, and installed footprint all increased. The current implementation added 180 nonblank source lines and 31 control-flow keywords. No package dependency was removed because the baseline already had none.

Exact LLM tokens and dollar savings were not measured. Muzzle did not invoke a model, and the environment had neither a provider usage receipt nor a compatible tokenizer. Reporting bytes as tokens would overstate the evidence.

## What remains

The highest-value next step is to preserve byte-bound execution while reducing its roughly half-second setup cost. A runtime-level open/copy/verify primitive could replace some shell launches, directory linking, duplicate hashing, and cleanup. A clean-host macOS/Linux regression job should establish latency, system-CPU, and large-script RSS budgets before optimization claims are published.

## Reproducing the results

The repository retains the Eval definition, benchmark scripts, raw samples, statistical summaries, capability evidence, native quality logs, and combined machine-readable result in `evaluation/hardening-2026-08/`. See its `README.md` for exact commands and fixed boundary SHAs.

## Conclusion

Muzzle v1.1.0 is demonstrably safer and more deterministic, with full evidence preservation and no dependency growth. It is also measurably slower and slightly larger. The hardening pass succeeded on security and reliability; performance optimization remains unfinished.
