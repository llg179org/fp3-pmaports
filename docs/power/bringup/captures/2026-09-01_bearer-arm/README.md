# A live data context makes the modem duty WORSE, and stops the LPASS sleeping

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
| **bearer up** (n=6 `logind`) | **48.8 %** | **~97 %** |
| no bearer, after the reboot (n=3, `mm=stopped`) | 33.4 % | ~0 % |
| no bearer, before the reboot (n=3, `mm=stopped`) | 36.8 % | ~0 % |
| the 2026-08-31 census, no bearer, `mm=running` (n=43) | 33.6 % | ~0 % |

Three independent signals move together, and all three move the wrong way:

1. **MPSS 34 % → 48.8 %.** Every one of the six rounds reads 48.3–49.1 %; the
   whole bearer-free population of 67 windows — daemon on and off, Wi-Fi up and
   down, cable in and out, before and after a reboot — spans 33.4–42.9 %. This
   run sits outside it.

2. ★ **The LPASS stops sleeping altogether.** Read the raw counter, not the
   percentage: in every bearer-free run the LPASS XO-off delta is 617–626 s
   across a 601 s window (a full-sleep reading that slightly overruns its own
   bracket, which is why the fitter prints `☠️IMPOS`). With the bearer up the
   same delta is **17–20 s**. The ADSP was awake for essentially the entire
   hour. Why a PDP context should hold the LPASS up is not explained here; the
   fact is what this capture records.

3. **The un-handshaked suspend path stops working.** The `rtcwake` rounds — the
   ones that bypass logind, so ModemManager's sleep handshake never runs — died
   after 1, 1, 1, 4, 21 and 216 s, every one of them on **`wakeup_irq=141`, the
   modem's SMD edge** (the same IRQ as the 2026-08-26 suspend-abort finding).
   The `logind` rounds, with the handshake, slept the full 600 s in all six.
   This is the first arm in which the internal A/B separates at all: with real
   network attachment present, the handshake is what keeps the AP asleep.

⇒ **The data context is not the lever, it is a cost.** And with it, the reading
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
