<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# burst-wlan-ab, 2026-08-27 13:41–14:01, pmOS 7.1.3 `#78-fp3` — the first real hit on front two

Three 360 s `burst-attrib` legs, `nmcli radio wifi off` between A and B. Panel
proven off for all 73 idle-ab samples of every leg. The ssh session was on the USB
link, which the tool checks before it will run.

| leg | wlan | n | floor | **median** | mean | p90 | max | mean mW | burst share |
|---|---|---|---|---|---|---|---|---|---|
| A | on | 179 | 53 | **99** | 119.0 | 221 | 293 | 497.5 | 67.6 % |
| **B** | **off** | 181 | **53** | **83** | 110.0 | **198** | 298 | 458.2 | 53.6 % |
| A′ | on | 179 | 53 | **98** | 114.1 | 217 | 331 | 473.7 | 59.8 % |

| statistic | A↔A′ spread | effect (baseline − B) | verdict |
|---|---|---|---|
| floor | 0.0 | **0.0** | nothing |
| **median** | **1.0** | **15.5 mA** | **15× the spread — real** |
| **p90** | 4.0 | **21.0 mA** | 5× the spread — real |
| mean | 4.9 | 6.5 | 1.3× — not established |
| mean mW | 23.8 | 27.4 | 1.2× — not established |
| burst share | 7.8 | 10.1 pt | 1.3× — not established |

**The wlan radio costs ~15 mA of median and ~21 mA at p90, and nothing at all on
the floor.** ☠️ The mean and the energy do **not** clear their own baseline
spread, so "wlan costs 27 mW" is not a measurement — the median and p90 are. Same
shape as the systemd PSI watch: it moves the *typical* sample, not the biggest
bursts. And B is n=1.

## ☠️ The obvious fix was dead before it was built

The natural conclusion — "power save is off, turn it on" — is wrong here. The
driver is `wcn36xx`; setting `debug_mask` to `WCN36XX_DBG_PMC` (0x2000) and
reading the log gives **`wcn36xx: Entered BMPS`**. Beacon-mode power save works.
NetworkManager reports `802-11-wireless.powersave: 0 (default)` and that default
is not leaving it off.

What the same log does show is churn: **8 BMPS entries in 180 s**, in clusters
(13207.0 / 13207.7 / 13230.4 / 13231.0 / 13231.6 / 13232.7 / 13241.4 / 13275.8 s).
Every entry implies a preceding exit, and between exit and re-entry the radio is
in full receive. With `wlan_pps` at 1–3, background broadcast — ARP, mDNS, IPv6 RA
— is enough to keep interrupting power save. ☠️ Some of that traffic may be ours:
the development host is on the same 192.168.100.x subnet as the phone's wlan.

## What it does not explain

With the radio entirely off, leg B still ran a **median of 83 mA against a floor
of 53**, and 97 of its 181 samples were still bursts. **Roughly 30 mA of burst
survives with wlan off, the modem excluded, the CPUs collapsed and the panel
dark.** That residue is what the rail census is for.
