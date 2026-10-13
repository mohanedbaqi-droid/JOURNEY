"""Prevent the observed loopTask stack overflow from large telemetry arrays."""
import sys
from pathlib import Path

matches = []
for path in Path(sys.argv[1]).rglob('*.su'):
    for line in path.read_text().splitlines():
        fields = line.split('\t')
        if len(fields) >= 3 and fields[0].endswith('void publishState()'):
            matches.append((path, int(fields[1]), fields[2]))
if not matches:
    raise SystemExit('Compiler stack-usage report for publishState is missing')
for path, size, kind in matches:
    print(f'publishState stack frame: {size} bytes ({kind})')
    if size > 2048 or kind not in ('static', 'dynamic,bounded'):
        raise SystemExit('publishState stack frame exceeds the bounded 2 KiB budget')
