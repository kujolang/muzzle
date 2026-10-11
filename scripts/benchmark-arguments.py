#!/usr/bin/env python3
"""Matched dry-run argument parsing benchmark; no host-dependent timing gate."""
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
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--sizes', type=int, nargs='+', default=[0, 25, 100])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 1 or any(size < 0 for size in args.sizes):
        parser.error('samples must be positive and sizes nonnegative')
    roots = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    env = dict(os.environ, KUJO_BIN=os.environ.get('KUJO_BIN', 'kujo'))
    results = []
    with tempfile.TemporaryDirectory(prefix='muzzle-arguments-') as temp:
        subprocess.run([str(roots['candidate'] / 'muzzle'), 'init'], cwd=temp,
                       env=env, check=True, capture_output=True)
        for size in args.sizes:
            values = [f'argument-{index}' for index in range(size)]
            samples = {label: [] for label in roots}
            for iteration in range(args.samples + 1):
                labels = list(roots) if iteration % 2 == 0 else list(reversed(roots))
                for label in labels:
                    start = time.perf_counter()
                    result = subprocess.run([str(roots[label] / 'muzzle'), 'run', 'hello-bash',
                                             *values, '--json', '--dry-run'], cwd=temp, env=env,
                                            check=True, capture_output=True, text=True)
                    elapsed = (time.perf_counter() - start) * 1000
                    receipt = json.loads(result.stdout)
                    assert not result.stderr, result.stderr
                    assert receipt['dry_run'] is True and receipt['args'] == values, receipt
                    assert receipt['runner'] == 'bash' and receipt['workflow'] == 'hello-bash'
                    assert not list((Path(temp) / '.muzzle/logs').iterdir())
                    if iteration:
                        samples[label].append(elapsed)
            results.append({'arguments': size, 'samples_ms': samples,
                            'median_ms': {label: statistics.median(times)
                                          for label, times in samples.items()}})
    output = {'runtime': subprocess.check_output([env['KUJO_BIN'], '--version'], text=True).strip(),
              'samples': args.samples, 'warmups': 1, 'results': results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({str(row['arguments']): row['median_ms'] for row in results}))


if __name__ == '__main__':
    main()
