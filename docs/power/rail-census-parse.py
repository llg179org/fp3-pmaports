#!/usr/bin/env python3
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
"""Turn a rail-census capture into the list of rails that vote active and never
vote sleep.

The qcom_rpm_smd_write tracepoint prints, per write:

    <state> <type>/<id> len=<n> <hex bytes>

where the payload is a run of RPM key-value pairs: a four-character key, a
32-bit length, then the value padded to four bytes. The keys that matter here
are "swen" (enable), "uv" (microvolts) and "ma" (load current).

☠️ A rail with an active vote and no sleep vote is not "unset" - the RPM uses
the active vote at all times, including under power collapse. That is the whole
point of the census: those rails stay up through suspend by construction, and
they are the ones with names printed under NO SLEEP VOTE below.
"""
import re
import struct
import sys
from collections import OrderedDict

LINE = re.compile(
    r'(?P<state>active|sleep)\s+(?P<type>\S{1,4})/(?P<id>\d+)\s+len=(?P<len>\d+)\s+(?P<hex>[0-9a-fA-F ]+)')

# The FP3 declares 3 SMPS and 16 LDOs; sdm632-fairphone-fp3.dts is the source.
FP3_RAILS = {
    'smpa': {3, 4, 5},
    'ldoa': {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 17, 19, 22, 23},
}


def parse_kvps(blob):
    out = OrderedDict()
    i = 0
    while i + 8 <= len(blob):
        key = blob[i:i + 4].rstrip(b'\x00').decode('ascii', 'replace')
        (n,) = struct.unpack('<I', blob[i + 4:i + 8])
        i += 8
        val = blob[i:i + n]
        i += (n + 3) & ~3
        if n == 4:
            out[key] = struct.unpack('<I', val)[0]
        else:
            out[key] = val.hex()
    return out


def main(path):
    votes = {}          # (type, id) -> {state: kvps}
    for line in open(path, errors='replace'):
        m = LINE.search(line)
        if not m:
            continue
        blob = bytes.fromhex(m.group('hex').replace(' ', ''))
        key = (m.group('type'), int(m.group('id')))
        votes.setdefault(key, {})[m.group('state')] = parse_kvps(blob)

    if not votes:
        print('no qcom_rpm_smd_write lines in the capture - was the tracepoint '
              'enabled, and did the buffer overflow?')
        return 1

    def fmt(k):
        if not k:
            return '-'
        return ' '.join(f'{n}={v}' for n, v in k.items())

    print(f'{"resource":12} {"active vote":34} {"sleep vote":34}')
    print('-' * 84)
    no_sleep = []
    for (typ, rid) in sorted(votes):
        v = votes[(typ, rid)]
        a, s = v.get('active'), v.get('sleep')
        print(f'{typ}/{rid:<7} {fmt(a):34} {fmt(s):34}')
        if a and not s:
            no_sleep.append((typ, rid, a))

    print(f'\n{len(votes)} resources voted, {len(no_sleep)} of them with NO '
          f'SLEEP VOTE:\n')
    for typ, rid, a in no_sleep:
        name = ''
        if typ in FP3_RAILS and rid in FP3_RAILS[typ]:
            name = f'  = pm8953_{"s" if typ == "smpa" else "l"}{rid} in the FP3 DT'
        en = a.get('swen')
        state = 'ENABLED' if en else ('disabled' if en == 0 else '?')
        print(f'  {typ}/{rid:<4} {state:9} {fmt(a)}{name}')

    print('\n☠️  Every line above with swen=1 is a rail held up through suspend '
          'by the absence of a sleep vote, not by anyone asking for it.')
    print('☠️  A rail appearing here is not thereby droppable - some must '
          'survive suspend. The next question is who its consumer is.')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
