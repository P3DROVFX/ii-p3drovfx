#!/usr/bin/env python3
"""Finite, read-only /proc sampler. Never starts/stops/reloads the shell.

Usage: python3 collect.py PID OUTPUT.json [SECONDS]
100% CPU means one fully busy logical CPU. No command arguments, environment,
user content, stack dumps or screenshots are retained. Standard library only.
"""
import collections
import datetime
import json
import os
from pathlib import Path
import re
import statistics
import sys
import time

PROC = Path('/proc')
HZ = os.sysconf('SC_CLK_TCK')
KEYS = {'Rss', 'Pss', 'Pss_Anon', 'Pss_File', 'Pss_Shmem',
        'Private_Clean', 'Private_Dirty', 'Swap', 'Size'}


def counters(path):
    out = {}
    for line in path.read_text().splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            if key in KEYS:
                out[key] = int(value.split()[0]) / 1024
    if 'Private_Clean' in out:
        out['Private'] = out['Private_Clean'] + out['Private_Dirty']
    return out


def stat(path):
    raw = (path / 'stat').read_text()
    name = raw[raw.index('(') + 1:raw.rindex(')')]
    fields = raw.rsplit(')', 1)[1].split()
    return {'name': name, 'ppid': int(fields[1]), 'startTicks': int(fields[19]),
            'cpuSeconds': (int(fields[11]) + int(fields[12])) / HZ,
            'waitedChildCpuSeconds': (int(fields[13]) + int(fields[14])) / HZ}


def label(path, name):
    # Script filenames identify a subsystem. Never print their arguments.
    args = (path / 'cmdline').read_bytes().split(b'\0')
    for arg in args[1:3]:
        value = arg.decode(errors='replace')
        if value.endswith(('.py', '.sh', '.js')) and value.startswith('/'):
            return Path(value).name
    return name


def tree(root):
    all_pids = {}
    for path in PROC.iterdir():
        if path.name.isdigit():
            try:
                all_pids[int(path.name)] = stat(path)
            except (OSError, ValueError):
                pass
    chosen = {root}
    while True:
        new = {pid for pid, s in all_pids.items() if s['ppid'] in chosen} - chosen
        if not new:
            break
        chosen.update(new)
    out = {}
    for pid in sorted(chosen):
        try:
            path = PROC / str(pid)
            s = all_pids[pid]
            s['label'] = label(path, s['name'])
            s['memoryMiB'] = counters(path / 'smaps_rollup')
            out[str(pid)] = s
        except (OSError, ValueError, KeyError):
            pass
    return out


def memory_maps(pid):
    groups = collections.defaultdict(collections.Counter)
    names = collections.defaultdict(collections.Counter)
    for line in (PROC / str(pid) / 'smaps').read_text().splitlines():
        if re.match(r'^[0-9a-f]+-[0-9a-f]+ ', line):
            fields = line.split(None, 5)
            name = fields[5] if len(fields) > 5 else '[anonymous]'
            if 'JSGCHeap:QtQml' in name:
                group = 'QML JavaScript GC heap'
            elif 'JITCode:QtQml' in name or 'JSVMStack:QtQml' in name:
                group = 'QML JIT and VM stack'
            elif name in ('[anonymous]', '[heap]'):
                group = 'anonymous native and other allocations'
            elif 'qmlcache' in name:
                group = 'mapped QML disk cache'
            elif re.search(r'\.(ttf|otf|ttc)', name):
                group = 'font files'
            elif name.startswith('/dev/') or 'dmabuf' in name:
                group = 'device mappings (not total VRAM)'
            elif '.so' in name:
                group = 'shared libraries including graphics drivers'
            else:
                group = 'other mappings'
        elif ':' in line:
            key, value = line.split(':', 1)
            if key in KEYS:
                amount = int(value.split()[0]) / 1024
                groups[group][key] += amount
                names[name][key] += amount
    return {'groupsMiB': dict(groups),
            'mappedFilesMiB': dict(sorted(names.items(), key=lambda x: -x[1]['Pss']))}


def thread_stats(pid):
    out = {}
    for path in (PROC / str(pid) / 'task').iterdir():
        try:
            out[path.name] = stat(path)
        except (OSError, ValueError):
            pass
    return out


def main():
    pid, output = int(sys.argv[1]), Path(sys.argv[2])
    duration = float(sys.argv[3]) if len(sys.argv) > 3 else 120.0
    identity = stat(PROC / str(pid))['startTicks']
    result = {'pid': pid, 'startedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'cpuConvention': '100% = one logical CPU', 'logicalCpus': os.cpu_count(),
              'intervalSeconds': 2, 'initialMaps': memory_maps(pid), 'samples': []}
    begin = time.monotonic()
    while True:
        if stat(PROC / str(pid))['startTicks'] != identity:
            raise RuntimeError('PID was reused; refusing to combine sessions')
        result['samples'].append({'elapsed': time.monotonic() - begin,
                                  'processes': tree(pid), 'threads': thread_stats(pid)})
        if time.monotonic() - begin >= duration:
            break
        time.sleep(min(2, duration - (time.monotonic() - begin)))
    result['finalMaps'] = memory_maps(pid)
    rows = []
    pids = sorted({p for s in result['samples'] for p in s['processes']}, key=int)
    for p in pids:
        values = [(s['elapsed'], s['processes'][p]) for s in result['samples'] if p in s['processes']]
        first, last = values[0], values[-1]
        elapsed = last[0] - first[0]
        rows.append({'pid': int(p), 'label': last[1]['label'], 'samples': len(values),
                     'observedSeconds': round(elapsed, 3),
                     'cpuPercent': round(100 * (last[1]['cpuSeconds'] - first[1]['cpuSeconds']) / elapsed, 3) if elapsed > 0 else None,
                     'medianMiB': {k: round(statistics.median(v['memoryMiB'][k] for _, v in values), 3)
                                   for k in ('Rss', 'Pss', 'Private')},
                     'pssRangeMiB': [round(min(v['memoryMiB']['Pss'] for _, v in values), 3),
                                     round(max(v['memoryMiB']['Pss'] for _, v in values), 3)]})
    result['summary'] = rows
    elapsed = result['samples'][-1]['elapsed'] - result['samples'][0]['elapsed']
    result['threadsSummary'] = []
    for tid, last in result['samples'][-1]['threads'].items():
        first = result['samples'][0]['threads'].get(tid)
        if first and first['startTicks'] == last['startTicks']:
            result['threadsSummary'].append({'tid': int(tid), 'name': last['name'],
                'cpuPercent': round(100 * (last['cpuSeconds'] - first['cpuSeconds']) / elapsed, 3)})
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'output': str(output), 'elapsedSeconds': round(elapsed, 3),
                      'processes': rows, 'threads': result['threadsSummary']}, indent=2))


if __name__ == '__main__':
    main()
