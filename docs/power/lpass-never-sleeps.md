> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# The audio DSP never sleeps, and the vendor's does

## The finding

**LPASS shut down twice since boot, for 0.12 s in total.** On the vendor stack,
on the same hardware, it shuts down thousands of times and keeps the XO off.

Read from `/sys/kernel/debug/qcom_rpm_master_stats/` on 2026-08-19, against the
Ubuntu Touch oracle capture of 2026-08-15
([`2026-08-15_ut_oracle_rpm-master-stats.txt`](2026-08-15_ut_oracle_rpm-master-stats.txt)):

| master | shutdowns, pmOS | XO duration, pmOS | shutdowns, UT | XO shutdowns, UT |
|---|---|---|---|---|
| APSS | 816 039 | **0** | 19 269 | **0** |
| MPSS | 83 790 | ~5.5 h | 1 151 | 1 132 |
| PRONTO | 230 552 | ~6.7 h | 3 045 | 3 045 |
| **LPASS** | **2** | **0.12 s** | **4 344** | **4 280** |
| TZ | 0 | 0 | 0 | 0 |

☠️ **The counter is live and was shown to be.** Over one 60 s window with the
phone idle: APSS +1038, MPSS +188, PRONTO +529, **LPASS +0**. Three counters
move and one does not, so "2" is a measurement rather than a stuck file - which
is the check that a number this convenient has to pass before it is believed.

The APSS row is a bonus consistency check: the vendor's application processor
does not shut the XO down either, which is independent confirmation that closing
the XO branch was right.

## Why it matters

`qcom_stats/vlow` and `vmin` have read **Count: 0** in every capture ever taken
on this device - through the PLL fix, the RPM handshake fix, the XO A/B, and the
leg that saved 36 mA by cutting the modem. The RPM enters a low-power mode only
when the masters let it. **A master that never shuts down is a sufficient
explanation for a gate that never opens**, and LPASS is the only one in that
state.

It also fits the shape of the rest of the investigation:

- Five userspace candidates measured, all zero. The current is not in a service.
- ~25 mA of the awake floor is the panel, accounted for.
- Awake and dark is ~58-63 mA; asleep is ~43-79 mA. **Suspend buys very little**,
  which is what a permanently-awake DSP would produce regardless of what the
  application processor does.

## What is NOT yet established

☠️ **That the sensor stack is the holder.** Stopping `snsregd` and
`iio-sensor-proxy` and waiting three minutes did not move the counter - but
three minutes is short, and the negative only says those two are not sufficient
on their own. Something else may hold it, or nothing may release it.

☠️ **That LPASS *can* shut down on this kernel at all.** The oracle proves the
hardware does it; it does not prove our firmware load, our q6 stack and our
sensor clients leave a path to it.

☠️ **That fixing it recovers a specific number.** No current has been attributed
to LPASS yet. This is a named mechanism for a gate, not a measured term.

## The next measurements, in order

1. **Who holds it.** The ADSP has clients on this kernel: the q6 audio stack
   (`q6afe`, `q6adm`, `q6asm`, `q6core`, `apr`) and the SMGR sensor drivers
   (`smgr`, `sns_smgr`, `smgr_accel/gyro/prox/mag`). Remove them in groups and
   watch the counter, longest-idle first.
2. **Whether it can.** If no combination moves it, the question becomes whether
   the ADSP is ever told it may sleep - the vendor sends explicit power-collapse
   requests over APR that mainline may simply not send.
3. **What it is worth.** Only once it moves: a slope leg with LPASS actually
   shutting down, against `baseline-20260819`.

☠️ Do not write a patch before step 1. The XO branch was mechanically plausible,
moved its counter from 0 to 1952, and changed the discharge slope by nothing.
