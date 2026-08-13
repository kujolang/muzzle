# Muzzle Performance Validation

Muzzle spools workflow stdout and stderr directly to the full local log. Quiet and JSON modes retain only bounded process metadata and, on failure, a short tail read through the system `tail` utility. This keeps agent-facing output and Muzzle's in-process capture independent of total log size.

Run the repeatable local benchmark:

```bash
bash scripts/benchmark.sh
```

Tune its bounded workload with `MUZZLE_BENCH_ITERATIONS` and `MUZZLE_BENCH_LINES`. The benchmark reports startup latency, full-log and JSON-summary sizes, peak resident memory, and concurrent-run duration. Results are local regression signals; compare runs on the same machine and Kujo build rather than publishing cross-machine claims.

The regression suite separately verifies that multi-megabyte workflow output produces a complete log and a compact JSON response. `tests/muzzle_process_regression.sh` verifies timeout, cancellation, and external termination behavior for descendant processes on Unix.
