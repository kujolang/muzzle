# Muzzle v1.1.0 Hardening Evaluation

This directory contains the matched before/after evaluation of the dedicated Muzzle hardening pass.

## Boundary

- Baseline: `75c2e1d20ed060b22df01c44d28221cd672a02fa`
- Current: `55c149271e3c6b81b993879d5bdd7f79e96a0cca` (`v1.1.0`)
- Comparison: identical workloads, one fixed Kujo release binary, alternating baseline/current order, three warmups, and at least ten measured samples.

The broader `v1.0.0` tag was not selected because 14 hardening and refactor commits occurred between that release and the explicitly recorded start of the dedicated audit. The choice is documented in the technical report.

## Contents

- `TECHNICAL_EVALUATION.md`: complete engineering evaluation.
- `PUBLIC_CASE_STUDY.md`: shorter publication-ready report.
- `eval-suite.json`: identical Kujo Eval outcome checks for both versions.
- `scripts/benchmark.mjs`: end-to-end latency, CPU, RSS, output, evidence, failure, and scaling samples.
- `scripts/helper-benchmark.mjs`: isolated execution-helper diagnostic used for root-cause attribution.
- `scripts/capability-evidence.sh`: matched security, artifact, contract, and installer workloads.
- `scripts/structure.mjs`: code/test/documentation footprint metrics.
- `scripts/install-footprint.mjs`: installed artifact footprint.
- `scripts/analyze.mjs`: statistical summaries.
- `scripts/assemble-results.mjs`: combined machine-readable receipt.
- `results/evaluation-results.json`: combined result.
- `results/runtime-raw.json`: raw end-to-end samples, including per-sample host load.
- `results/eval/`: Kujo Eval reports and detailed results.

## Reproduction

From the Muzzle repository root, create detached worktrees at the exact boundary commits:

```bash
git worktree add --detach /tmp/muzzle-hardening-baseline 75c2e1d20ed060b22df01c44d28221cd672a02fa
git worktree add --detach /tmp/muzzle-hardening-current 55c149271e3c6b81b993879d5bdd7f79e96a0cca
```

Set fixed tool paths. Both versions must use the same Kujo binary and module tree:

```bash
export MUZZLE_EVAL_KUJO=/absolute/path/to/kujo/target/release/kujo
export MUZZLE_EVAL_MODULES=/absolute/path/to/kujo/modules
export MUZZLE_EVAL_FRAMEWORK=/absolute/path/to/eval
```

Capture matched capability evidence and score it with the same Eval suite:

```bash
evaluation/hardening-2026-08/scripts/capability-evidence.sh \
  /tmp/muzzle-hardening-baseline /tmp/muzzle-hardening-current \
  "$MUZZLE_EVAL_KUJO" "$MUZZLE_EVAL_MODULES" \
  evaluation/hardening-2026-08/results/capabilities "$(command -v openssl)"

evaluation/hardening-2026-08/scripts/run-eval.sh \
  "$MUZZLE_EVAL_FRAMEWORK" "$MUZZLE_EVAL_KUJO" "$MUZZLE_EVAL_MODULES" \
  evaluation/hardening-2026-08/results/capabilities/baseline \
  evaluation/hardening-2026-08/results/eval/baseline || true

evaluation/hardening-2026-08/scripts/run-eval.sh \
  "$MUZZLE_EVAL_FRAMEWORK" "$MUZZLE_EVAL_KUJO" "$MUZZLE_EVAL_MODULES" \
  evaluation/hardening-2026-08/results/capabilities/current \
  evaluation/hardening-2026-08/results/eval/current
```

Run the paired benchmark only on a stable host. The script refuses to start above its load threshold:

```bash
evaluation/hardening-2026-08/scripts/benchmark.mjs \
  --baseline /tmp/muzzle-hardening-baseline \
  --current /tmp/muzzle-hardening-current \
  --kujo-bin "$MUZZLE_EVAL_KUJO" \
  --kujo-modules "$MUZZLE_EVAL_MODULES" \
  --output evaluation/hardening-2026-08/results/runtime-raw.json \
  --warmups 3 --runs 10 --max-load 12

evaluation/hardening-2026-08/scripts/analyze.mjs \
  evaluation/hardening-2026-08/results/runtime-raw.json \
  evaluation/hardening-2026-08/results/runtime-results.json
```

Collect structural and installed-footprint measurements:

```bash
evaluation/hardening-2026-08/scripts/structure.mjs \
  /tmp/muzzle-hardening-baseline /tmp/muzzle-hardening-current \
  evaluation/hardening-2026-08/results/structure.json

evaluation/hardening-2026-08/scripts/install-footprint.mjs \
  /tmp/muzzle-hardening-baseline /tmp/muzzle-hardening-current \
  evaluation/hardening-2026-08/results/install-footprint.json
```

Run each revision's native gate with the same Kujo runtime:

```bash
(cd /tmp/muzzle-hardening-baseline && KUJO_BIN="$MUZZLE_EVAL_KUJO" KUJO_MODULE_PATH="$MUZZLE_EVAL_MODULES" make quality)
(cd /tmp/muzzle-hardening-current && KUJO_BIN="$MUZZLE_EVAL_KUJO" KUJO_MODULE_PATH="$MUZZLE_EVAL_MODULES" make quality)
```

Remove only the two evaluation worktrees when finished:

```bash
git worktree remove /tmp/muzzle-hardening-baseline
git worktree remove /tmp/muzzle-hardening-current
```

## Interpretation Rules

- Median is the primary latency statistic.
- p95 and p99 are observed order statistics; p99 is not treated as stable with `n=10` or `n=15`.
- A difference smaller than the observed run-to-run noise is classified as inconclusive.
- Exact bytes and lines are reported for agent-facing output. Exact provider token counts are not claimed because no provider tokenizer or usage receipt was available.
- The isolated helper benchmark is diagnostic evidence only when host load is high; end-to-end results take precedence.
