# Muzzle Performance Validation

Muzzle spools workflow stdout and stderr directly to the full local log. Quiet and JSON modes retain only bounded process metadata and, on failure, a short excerpt from a streaming `awk` redaction scan. Redaction scans from the beginning so distant key-block markers remain effective. It retains the last five redacted lines, each at most 4,096 characters; oversized lines receive an explicit omission notice and remain intact in the full log. The scanner has a five-second deadline and reports an unavailable excerpt if it cannot finish. Muzzle capture stays bounded; the external awk process can allocate memory proportional to the longest input line.

Run the repeatable local benchmark:

```bash
bash scripts/benchmark.sh
```

Tune its bounded workload with `MUZZLE_BENCH_ITERATIONS` and `MUZZLE_BENCH_LINES`. The benchmark reports startup latency, full-log and JSON-summary sizes, peak resident memory, and concurrent-run duration. Results are local regression signals; compare runs on the same machine and Kujo build rather than publishing cross-machine claims.

The regression suite separately verifies that multi-megabyte workflow output produces a complete log and a compact JSON response. `tests/muzzle_process_regression.sh` verifies timeout, cancellation, and external termination behavior for descendant processes on Unix.

Snapshot preparation batches sibling links into at most 64 sources and approximately
16 KiB of source-path arguments per `ln` invocation. Digest checks, private snapshots,
relative imports, and cleanup remain in place. Compare two checkouts with the same
snapshot helper interface using Python 3 (development only):

```bash
python3 scripts/benchmark-snapshot.py --baseline /path/to/baseline-checkout --output /tmp/snapshot-results.json
```

This alternates baseline/current samples after two warmups, with ten measured runs
for projects containing 0, 100, and 1,000 root entries. It verifies output and cleanup
for every sample. Raw measurements are in the output JSON. Timing is informational;
CI gates the bounded subprocess count and behavior instead of host-sensitive latency.

Retention cleanup sorts artifact ranks once instead of comparing every artifact
against every other artifact. `--keep` still counts independently per workflow and
file type, by numeric timestamp and then filename; age and workflow filters do not
change those ranks. Selection receipts retain their original deterministic order.
Only confined regular files with a valid workflow name, decimal timestamp, and
32-character hexadecimal identifier are eligible for cleanup.

Measure matched retention selection with an independent expected-result check:

```bash
KUJO_BIN=kujo python3 scripts/benchmark-retention.py --baseline /path/to/baseline-checkout --output /tmp/retention-results.json
```

The benchmark uses one warmup and five alternating measured samples per checkout
at 60, 300, and 900 artifacts. Every dry-run sample verifies the selected paths and
that no evidence was deleted. Timing is informational; behavioral regression tests
cover timestamp widths, ties, large keep counts, filters, and unrecognized files.
