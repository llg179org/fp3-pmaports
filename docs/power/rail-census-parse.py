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

# The FP3 declares 3 SMPS and 16 LDOs, and every consumer below was parsed out
# of sdm632-fairphone-fp3.dts. A census line reading "ldoa/8" is a number; the
# same line reading "sdhc_1:vmmc - THE eMMC" is a decision.
#
# ☠️ NOSLEEP marks rails that must not be dropped in suspend whatever the census
# says: l5/l8 are the eMMC's vqmmc and vmmc, l11/l12 are the SD slot's. This
# device's eMMC has already fallen off the bus once, with -110 and emergency_ro.
FP3_RAILS = {
    ('smpa', 3): 'camss:vdda, mdss_dsi0:vdda, parent of l1/l2/l3',
    ('smpa', 4): 'parent of l4 l5 l6 l7 l16 l19',
    ('smpa', 5): 'NO CONSUMER IN DT',
    ('ldoa', 1): 'NO CONSUMER IN DT',
    ('ldoa', 2): 'camera@1a:vdig',
    ('ldoa', 3): 'hsusb_phy:vdd, mdss_dsi0_phy:vcca',
    ('ldoa', 5): 'NOSLEEP sdhc_1:vqmmc (eMMC), wcnss:vddpx, wcnss_iris:vdddig, aw8898:dvdd/vddio',
    ('ldoa', 6): 'panel@0:iovcc',
    ('ldoa', 7): 'hsusb_phy:vdda-pll, mpss:pll (modem PLL), wcnss_iris:vddxo',
    ('ldoa', 8): 'NOSLEEP sdhc_1:vmmc (eMMC)',
    ('ldoa', 9): 'wcnss_iris:vddpa',
    ('ldoa', 11): 'NOSLEEP sdhc_2:vmmc (SD slot)',
    ('ldoa', 12): 'NOSLEEP sdhc_2:vqmmc (SD slot)',
    ('ldoa', 13): 'hsusb_phy:vdda-phy-dpdm',
    ('ldoa', 16): 'NO CONSUMER IN DT',
    ('ldoa', 17): 'NO CONSUMER IN DT',
    ('ldoa', 19): 'wcnss_iris:vddrfa',
    ('ldoa', 22): 'camera@10:vdda, camera@1a:vana',
    ('ldoa', 23): 'NO CONSUMER IN DT',
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
    held = 0
    for typ, rid, a in no_sleep:
        who = FP3_RAILS.get((typ, rid), 'not a rail this DT declares')
        rail = f'pm8953_{"s" if typ == "smpa" else "l"}{rid}'
        en = a.get('swen')
        state = 'ENABLED' if en else ('disabled' if en == 0 else '?')
        if en:
            held += 1
        print(f'  {typ}/{rid:<4} {rail:11} {state:9} {fmt(a)}')
        print(f'  {"":17} {who}')

    print(f'\n{held} of them are ENABLED - held up through suspend by the '
          'absence of a sleep vote, not because anyone asked for it.')
    print('☠️  A rail appearing here is not thereby droppable. Anything marked '
          'NOSLEEP above is the eMMC or the SD slot and is off the table; '
          'ldoa/7 feeds the modem PLL.')
    print('☠️  NO CONSUMER IN DT with swen=1 means no Linux driver is holding '
          'it, so no consumer-intent work in the regulator layer can drop it - '
          'that is the RPM boot state or another master, a different question.')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
