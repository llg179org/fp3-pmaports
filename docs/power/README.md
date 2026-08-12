# Power measurements on the Fairphone 3

> ⚠️ **AI-generated.** These pages, and the code and measurements they describe,
> were written by Claude (Opus 5) working under the direction of Lajosházi,
> László Gergely, who reviewed every change and made or reviewed every
> measurement they rest on.

Raw captures from the charger and power-management work, kept because the
conclusions drawn from them are only as good as the data, and because a host
reboot has already eaten one of these files once.

Each log is one line per sample with the same fields on both operating systems,
so the two can be compared directly:

```
iso_time uptime_s capacity status charge_type vbat_uV ibat_uA temp_dC
usb_online usb_imax_uA usb_vbus_uV usb_real_type charge_done chgr_status_reg
```

`usb_real_type` and `charge_done` exist only on the vendor stack; the columns
are kept on the pmOS side with `-` so the files line up. `chgr_status_reg` is
`BATTERY_CHARGER_STATUS_1` read straight from the PMIC — its low three bits are
the charger's own state machine, and code 5 is the one that says a charge
finished.

| file | what it holds |
|---|---|
| `2026-08-11_regs-pmos.txt`, `2026-08-11_regs-ut.txt` | the charger's CHGR, DCDC, BATIF, USB and MISC registers, 1280 of them, read on each OS with the same pack in the same state. 45 differed; `CHGR_CFG2` was the one that mattered |
| `2026-08-11_ut_discharge-charge.txt` | Ubuntu Touch: a night idle, a deliberate flash+camera load, then a full charge to termination |
| `2026-08-12_ut_terminates.txt` | the vendor stack reaching `TERMINATE` within a minute of the current crossing the threshold |
| `2026-08-12_pmos_iterm-fix-terminates.txt` | the same on pmOS, after `I_TERM_BIT` was left set — the single-change A/B |
| `2026-08-12_pmos_idle-discharge.txt` | pmOS idle, matched against the UT night |
| `2026-08-12_pmos_day-to-r51-termination.txt` | a day on pmOS ending in the first termination reached by the **packaged** kernel rather than by hand-deployed pieces: `linux-fp3-7.1.3-r51`, taper at 87 mA, then `Full` with `chgr_status_reg` at `0x45`. The uptime column resets partway through, at the reboot onto that package |

## What these say, and what they do not

**Percent is not comparable between the two.** They run different gauges. Over
one matched 6.66 h idle window the vendor gauge reported 6 points against 571
mAh integrated, and ours reported 36 points against 1319 mAh. Compare the
integrated current and the terminal voltage; treat the percentage as a
measurement *of the gauge*, not of the phone.

**The logger biases its own numbers.** It wakes once a minute and reads the
current while it is itself running, so the mean it produces is high. This is
identical on both sides, so the difference between them survives; the absolute
figure does not.

**Idle here means idle with the link up.** Every one of these ran with WiFi
associated and an SSH session open, because that is how the data got off the
phone. None of them is a measurement of a sleeping phone. pmOS in particular
never suspended at all during these runs — `/sys/power/suspend_stats/success`
stayed at 0, because `sleep-inactive-battery-type` is `nothing`, not because
anything blocked it.

**One number here still has no explanation, and the leading candidate is now
ruled out.** pmOS idled at 198 mA against Ubuntu Touch's 86 mA. That pmOS never
suspends is measured — but so is the other side, as of 2026-08-12: **Ubuntu
Touch does not suspend either.**

The counter alone could not say so, because `success` is since boot and the
oracle slot had just been rebooted. What settles it is comparing the two clocks,
which needs no counter and no root: `CLOCK_MONOTONIC` does not advance across a
suspend, so an idle phone that sleeps shows less uptime than wall time. Sampled
twice five minutes apart on UT, with the display off and nothing but the SSH
link up:

```
1786567461 436
1786567491 466      # 30 s of wall clock, 30 s of uptime — awake the whole way
```

Neither kernel offers `/sys/power/autosleep` at all. The vendor one has the
Android wakelock interface (`/sys/power/wake_lock`, owned by `radio`) and would
suspend on a userspace daemon's say-so; ours has neither the interface nor
anything asking. So the 2.3x gap is **not** a sleeping phone against a waking
one: it is two awake phones, one of which costs more to keep awake.

Where that goes next is runtime PM, measured the same way on both sides — the
same two-sided diff that found the charger bug:

| | Ubuntu Touch | postmarketOS |
|---|---|---|
| devices with runtime PM `active` | 8 | **17** |
| `suspended` | 65 | 46 |
| `unsupported` (no runtime PM at all) | 719 | 293 |

The totals are not comparable — the vendor kernel enumerates far more devices —
but the `active` list is. Ours keeps two i2c buses and a USB PHY awake that the
vendor stack does not, and one of them is `i2c 0-000c`, which is the aw8898
speaker amplifier: the part whose PLL is [known never to
lock](../audio/README.md) on this port, leaving the driver to park the chip.
That is a lead and not a finding — nothing here measures what any of those
devices costs.
