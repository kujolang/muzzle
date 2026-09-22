#!/usr/bin/env python3
"""Matched helper benchmark; compare two checkouts with the digest/snapshot API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=Path, required=True)
parser.add_argument('--current', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--runs', type=int, default=10)
args = parser.parse_args()
if args.runs < 10:
    parser.error('--runs must be at least 10')
roots = {label: root.resolve() for label, root in [('baseline', args.baseline), ('current', args.current)]}
records = []
with tempfile.TemporaryDirectory(prefix='muzzle-snapshot-benchmark-') as temporary:
    for entries in [0, 100, 1000]:
        project = Path(temporary) / str(entries)
        for name in ['workflows', 'logs', 'state']:
            (project / '.muzzle' / name).mkdir(parents=True, exist_ok=True)
        for index in range(entries):
            (project / f'entry-{index}').touch()
        script = project / '.muzzle/workflows/probe.sh'
        script.write_text("printf 'snapshot-ok\\n'\n")
        digest = hashlib.sha256(script.read_bytes()).hexdigest()
        for sample in range(-2, args.runs):
            labels = ['baseline', 'current'] if sample % 2 else ['current', 'baseline']
            for label in labels:
                command = ['bash', str(roots[label] / 'src/muzzle_exec.sh'), 'bash', '.muzzle/workflows/probe.sh',
                           digest, '.muzzle/state/executions/' + 'b' * 32, '.muzzle/logs/probe.log', 'false',
                           os.environ.get('KUJO_BIN', 'kujo'), '--']
                start = time.perf_counter()
                result = subprocess.run(command, cwd=project, capture_output=True)
                elapsed = (time.perf_counter() - start) * 1000
                if result.returncode or (project / '.muzzle/logs/probe.log').read_bytes() != b'snapshot-ok\n':
                    raise RuntimeError(f'{label} failed: {result.stderr!r}')
                if list((project / '.muzzle/state/executions').iterdir()):
                    raise RuntimeError('Snapshot was not cleaned')
                records.append(dict(label=label, entries=entries, sample=sample, warmup=sample < 0, wall_ms=elapsed))
summary = []
for entries in [0, 100, 1000]:
    for label in roots:
        values = [r['wall_ms'] for r in records if r['entries'] == entries and r['label'] == label and not r['warmup']]
        summary.append(dict(entries=entries, label=label, median_ms=round(statistics.median(values), 2),
                            min_ms=round(min(values), 2), max_ms=round(max(values), 2)))
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(dict(platform=platform.platform(), runs=args.runs, warmups=2,
                                      roots={k: str(v) for k, v in roots.items()}, summary=summary,
                                      records=records), indent=2) + '\n')
print(json.dumps(summary, indent=2))
