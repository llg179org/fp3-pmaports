# ☠️☠️ RETRACTED — the 48.8 % was the BAND, not the data context

> **Superseded 2026-09-01 16:53, four hours after it was written.** The
> [band ladder](../2026-09-01_band-ladder/README.md) run the same afternoon reads
> **48.8 % and 51.6 % on eutran-1** and 31.8 / 34.1 % on eutran-3 and eutran-20.
> This page's headline number is 48.8 %, its band was never recorded — the column
> did not exist yet — and no other arm measured today lands anywhere near it. The
> data context is therefore **not shown to cost anything**; the arm has to be
> repeated with the band locked on both legs.
>
> What survives: the bearer came up at all (the IPA finding below, since confirmed
> directly), it stayed up for the whole run, and the `rtcwake` rounds died on the
> modem's SMD edge while the handshaked rounds slept — that last one is about the
> suspend path, not about duty, and is not touched by the band.
>
> The rest of the page is kept unedited as the record of what was claimed.

# A live data context makes the modem duty WORSE — and it is ModemManager, not the context, that keeps the ADSP awake

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 13:19 → 14:33, **12 rounds** (6 `logind`, all of which slept the full
601 s), cable in with the input cut, Wi-Fi up, panel dark, ModemManager running
— and, for the first time on pmOS, **an established PDP context**:

```
mmcli -m any --simple-connect='apn=internet.vodafone.net'
  -> Bearer/1  connected: yes  multiplexed: yes  interface: qmapmux0.0
     10.112.79.62/30  gw 10.112.79.61  dns 80.244.99.37
ip link set qmapmux0.0 up ; ip addr add 10.112.79.62/30 dev qmapmux0.0
  -> 3/3 ping to 8.8.8.8 over LTE
```

The host-side IP configuration had to be done by hand: pmOS has no `netmgrd`
and no `ipacm`, so nothing brings `qmapmux0.0` up on its own. The modem side
needed nothing beyond the connect.

**Pre-registered:** ~5–8 % ⇒ the D-track lever is found, and the explanation is
that a modem without a context never uses deep DRX. ~34 % ⇒ the data context is
not it either, and the 2026-08-31 morning episode stays unexplained.

## Result: 48.8 % — the arm moved the wrong way

| arm (same cable/Wi-Fi/panel state) | MPSS awake | LPASS awake |
|---|---:|---:|
| **bearer up** (n=6 `logind`, `mm=running`) | **48.8 %** | ~97 % awake |
| no bearer, after the reboot (n=3, `mm=stopped`) | 33.4 % | asleep |
| no bearer, before the reboot (n=3, `mm=stopped`) | 36.8 % | asleep |
| the 2026-08-31 census, no bearer, `mm=running` (n=43) | 33.6 % | ☠️ **~96 % awake** |

☠️ The last row's LPASS column is the one that broke the first version of this
page: read point 2 below before using the column at all.

Three signals move; **only the first two are the bearer's**, and the third is
corrected below:

1. **MPSS 34 % → 48.8 %.** Every one of the six rounds reads 48.3–49.1 %; the
   whole bearer-free population of 67 windows — daemon on and off, Wi-Fi up and
   down, cable in and out, before and after a reboot — spans 33.4–42.9 %. This
   run sits outside it.

2. ☠️☠️ **RETRACTED WITHIN THE HOUR, and the retraction is the better finding.**
   What stood here said the bearer stops the LPASS sleeping: 17–20 s of XO-off
   per 601 s window against 617–626 s "in every bearer-free run". The second
   half was never checked. It is false — and checking it named the real
   variable, which is **ModemManager**, not the bearer:

   | run | `mm` | bearer | n | LPASS XO-off, median | MPSS awake |
   |---|---|---|---:|---:|---:|
   | 2026-08-31 census | **running** | no | 43 | **27 s** (awake) | 33.7 % |
   | 2026-09-01 night control | stopped | no | 43 | 617 s (asleep) | 36.0 % |
   | 2026-09-01 Wi-Fi arm | stopped | no | 12 | 618 s | 36.7 % |
   | 2026-09-01 cable arm | stopped | no | 11 | 618 s | 35.7 % |
   | 2026-09-01 core cycle | stopped | no | 6 | 618 s | 37.2 % |
   | **this run** | **running** | **yes** | 6 | **19 s** (awake) | 48.8 % |

   The split is perfect on `mm` and has nothing to do with the bearer. ★ **With
   ModemManager running, the ADSP does not shut its crystal down across a 600 s
   suspend; with it stopped, it does so for the whole window.** That separates
   *within one boot* — the 08-31 census and the night control are the same boot
   — so it is not the reboot, and it is 49 rounds against 72.

   ☠️ The error was a bounded search: five runs were in front of me and I read
   the four that agreed. The A′ control below decides it directly, because it is
   `mm=running` with no bearer — the cell this table is missing.

3. **The un-handshaked suspend path stops working.** The `rtcwake` rounds — the
   ones that bypass logind, so ModemManager's sleep handshake never runs — died
   after 1, 1, 1, 4, 21 and 216 s, every one of them on **`wakeup_irq=141`, the
   modem's SMD edge** (the same IRQ as the 2026-08-26 suspend-abort finding).
   The `logind` rounds, with the handshake, slept the full 600 s in all six.
   This is the first arm in which the internal A/B separates at all: with real
   network attachment present, the handshake is what keeps the AP asleep.

⇒ **The data context is not the lever, it is a cost** — of about 15 points of
modem duty, which is the one claim on this page that survives its own
correction, both of its rows being `mm=running`. And with it, the reading
that a live data path is what makes the oracle cheap — "the three-times-cheaper
system is the one that does MORE" — does not survive as stated: merely holding a
PDP context up on pmOS is worth +15 pp of modem duty and an ADSP that never
sleeps. Whatever the oracle does differently, it is not *having a context*.

## Housekeeping

- **The bearer stayed up for the whole run**, which was the pre-registered
  requirement: `attempts: 1` and `connected: yes` when the run ended, with
  252 bytes each way. Its `duration` counter reads 1350 s against 5190 s of wall
  time, and the difference is exactly the suspended time — the counter freezes
  across suspend, it did not restart.
- The controls carry `mm=stopped` while this arm needs `mm=running` (the bearer
  falls over without the daemon). That is covered by
  [`../2026-09-01_modem-night-control/`](../2026-09-01_modem-night-control/README.md),
  which measured the daemon's own effect on duty as none (33.6 → 35.7 %), and by
  the 2026-08-31 census row above, which is `mm=running` and reads 33.6 %.
- The waking IRQ is `54:pm8xxx_rtc_alarm` here and `56:` in the pre-reboot
  captures: the number shifted across the 2026-09-01 reboot, the source did not.

## ☠️ No current figure from this run

`sleep-night-fit.py` prices the six rounds at 251 mA, the post-reboot control at
335 mA and the pre-reboot control at 261 mA — an ordering that contradicts the
duty ordering, on an rms residual of 42 mAh. At 3.6 V and one hour the voltage
samples move ±26 mV between rounds (round 10 reads *above* round 8), which is
±76 mA of slope on its own. **The current instrument needs a night; this window
resolves duty only.** The mA numbers are recorded here so nobody re-derives them
and believes them.
