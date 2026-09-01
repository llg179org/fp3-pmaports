# A modem power cycle does not reset the duty — the state is not in the modem core

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 10:36 → 11:44, **6 rounds**, cable in with the input cut, Wi-Fi up,
panel dark, ModemManager stopped — the same arm as
[`../2026-09-01_cable-in-arm/`](../2026-09-01_cable-in-arm/README.md), run
immediately after a modem-core power cycle.

## The cycle

```
mmcli -m any --disable            # registered -> disabled
mmcli -m any --set-power-state-low
mmcli -m any --set-power-state-on
mmcli -m any --enable             # -> registered, lte, attached, vodafone HU
```

Verified at each step; the modem came back to exactly the state of leg B of
[`../2026-08-31_mm-duty-ab/`](../2026-08-31_mm-duty-ab/README.md), which read
4.9 %.

**Pre-registered:** ~5 % ⇒ the state lives in the modem core and is resettable
without a reboot, i.e. a workaround exists. ~36 % ⇒ it is not the modem core's
state and the reboot test is still needed.

## Result: 37.4 %

| | MPSS awake |
|---|---:|
| `logind` rounds (n=3) | 36.8 % |
| `rtcwake` rounds (n=3) | 37.9 % |
| the same arm before the cycle (n=12) | 35.5 / 36.2 % |

Unchanged, and if anything marginally higher. **Powering the modem core down and
back up does not restore the low-duty state.** No workaround at this layer.

⇒ The state survives a full modem power-down, so it is not held in the modem's
own volatile state. What remains: the AP side (drivers, the QMI/QRTR link, the
IPC router's own state), the network's view of this subscriber, or simple
elapsed time. The reboot test separates the first from the last two, and it is
next.

## Housekeeping

All six rounds slept the full 600 s and ended on `56 pm8xxx_rtc_alarm`, with no
daemon running — the fourth independent confirmation that nothing wakes the AP
when ModemManager is absent.
