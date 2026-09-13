#!/usr/bin/env python3
"""Sample a process's real resident/proportional/private memory, read-only.

When launched by a Quickshell Process, the default PID is that running shell.
This does not open windows, send IPC, capture input or start another shell.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import time


def sample(pid):
    values = {}
    for line in (Path('/proc') / str(pid) / 'smaps_rollup').read_text().splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        if key in ('Rss', 'Pss', 'Private_Clean', 'Private_Dirty', 'Swap'):
            values[key] = int(value.split()[0]) / 1024
    values['Private'] = values.pop('Private_Clean') + values.pop('Private_Dirty')
    # Account for spaces/parentheses in comm before reading stat fields.
    fields = (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
    values['cpuSeconds'] = (int(fields[11]) + int(fields[12])) / os.sysconf('SC_CLK_TCK')
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, default=os.getppid())
    parser.add_argument('--label', default='sample')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--samples', type=int, default=7)
    args = parser.parse_args()
    start = time.monotonic()
    samples = []
    for index in range(max(1, args.samples)):
        if index:
            time.sleep(0.25)
        samples.append(sample(args.pid))
    elapsed = time.monotonic() - start
    result = {'pid': args.pid, 'label': args.label, 'unit': 'MiB', 'samples': len(samples),
              'median': {key: round(statistics.median(s[key] for s in samples), 3)
                         for key in samples[0] if key != 'cpuSeconds'},
              'range': {key: [round(min(s[key] for s in samples), 3), round(max(s[key] for s in samples), 3)]
                        for key in samples[0] if key != 'cpuSeconds'},
              'cpuPercent': (round(100 * (samples[-1]['cpuSeconds'] - samples[0]['cpuSeconds']) / elapsed, 2)
                             if len(samples) > 1 else None)}
    encoded = json.dumps(result)
    if args.output:
        with args.output.open('a') as output:
            output.write(encoded + '\n')
    print(encoded)


if __name__ == '__main__':
    main()
