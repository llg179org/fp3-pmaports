# The USB link is not the lever either — and that exhausts the configuration space

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 08:15 → 10:25, **12 rounds**, cable **in** with the PMIC input cut
(`echo Unknown > .../pmi632-charger/status`, battery gated to `Discharging`),
Wi-Fi up, panel dark, ModemManager stopped. Battery 47 %.

Tool: [`../../tools/modem-night.sh`](../../tools/modem-night.sh) `2 600 15 stopped up in`.
[`fit.txt`](fit.txt), raw in [`raw/`](raw/).

## Result

| arm | cable | Wi-Fi | MPSS awake |
|---|---|---|---:|
| control | out | down | 35.7 % |
| Wi-Fi arm | out | up | 36.2 % |
| **this arm** | **in, input cut** | up | **35.5 % (logind) / 36.2 % (rtcwake)** |

The CDC-NCM link is enumerated in this arm and absent in the other two, and the
duty does not move. **The USB link is not what separated the 5 % episode from
every later window.** All 12 rounds slept the full 600 s and ended on the RTC.

## ☠️ And that is the point at which the configuration hypothesis ran out

Three arms, three variables — the daemon, Wi-Fi, the cable — and 67 windows, all
between 33.4 % and 42.9 %. Nothing moved it.

The reason is in [`../2026-08-31_mm-duty-ab/`](../2026-08-31_mm-duty-ab/README.md)
and in `uptime`, not in any of these arms: **every one of these measurements, and
the 5 % episode itself, comes from a single uninterrupted boot** started
2026-08-30 14:00:11. The duty was 4.9–5.1 % at 16 h of uptime and 33.6–36.2 %
from 22 h onwards, and it has not come back down in 28 hours.

⇒ The variable was never a configuration. The next measurement is a **reboot**,
and it is fifteen minutes: bring the phone up, run this exact arm again at low
uptime, and compare against these 12 windows. Same script, same flags, same cable
state — only the uptime differs.

☠️ It also means these three arms were not wasted but were the wrong axis, and
the instrument that would have said so — [`../../tools/duty-vs-uptime.sh`](../../tools/duty-vs-uptime.sh),
"is the modem's awake duty a per-BOOT constant, or does it DECAY after a boot?" —
already existed in this repository, unrun, while three configuration arms were
spent.
