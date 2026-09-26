#!/usr/bin/env python3
"""Matched retention timings with selection-equivalence checks (stdlib only)."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--sizes', type=int, nargs='+', default=[60, 300, 900])
    args = parser.parse_args()
    if args.samples < 1 or any(size < 1 for size in args.sizes):
        parser.error('samples and sizes must be positive')
    roots = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    results = []
    with tempfile.TemporaryDirectory(prefix='muzzle-retention-') as temp:
        project = Path(temp)
        subprocess.run([str(roots['baseline'] / 'muzzle'), 'init'], cwd=project,
                       check=True, capture_output=True)
        logs = project / '.muzzle/logs'
        for size in args.sizes:
            for old in logs.iterdir():
                old.unlink()
            paths = []
            for index in range(size):
                name = f'job-{index % 3}-{1000 + index // 2}-{index:032x}.log'
                (logs / name).write_text('retained evidence\n')
                paths.append((name, index % 3, 1000 + index // 2))
            expected = {'.muzzle/logs/' + name for name, group, timestamp in paths
                        if sum((t, n) > (timestamp, name) for n, g, t in paths if g == group) >= 5}
            samples = {label: [] for label in roots}
            for iteration in range(args.samples + 1):
                order = list(roots) if iteration % 2 == 0 else list(reversed(roots))
                for label in order:
                    start = time.perf_counter()
                    process = subprocess.run([str(roots[label] / 'muzzle'), 'clean', '--keep', '5',
                                              '--dry-run', '--json'], cwd=project,
                                             capture_output=True, text=True, check=True)
                    elapsed = (time.perf_counter() - start) * 1000
                    receipt = json.loads(process.stdout)
                    assert not process.stderr, process.stderr
                    assert {a['path'] for a in receipt['artifacts']} == expected
                    assert receipt['selected'] == len(expected) and receipt['removed'] == 0
                    assert len(list(logs.iterdir())) == size
                    if iteration:
                        samples[label].append(elapsed)
            results.append({'artifacts': size, 'selected': len(expected), 'samples_ms': samples,
                            'median_ms': {k: statistics.median(v) for k, v in samples.items()}})
    payload = {'method': 'one warmup per checkout/size; alternating paired runs; keep=5 across 3 workflows',
               'runtime': subprocess.check_output([os.environ.get('KUJO_BIN', 'kujo'), '--version'], text=True).strip(),
               'results': results}
    args.output.write_text(json.dumps(payload, indent=2) + '\n')
    print(json.dumps([{'artifacts': r['artifacts'], **r['median_ms']} for r in results]))


if __name__ == '__main__':
    main()
