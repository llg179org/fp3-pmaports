# The raw captures

> ⚠️ **AI-generated.** Maintained by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

Every number in [`../../README.md`](../../README.md) came from a file in this
directory. They are kept because the conclusions are only as good as the data,
and because a host reboot has already eaten one of these files once.

☠️ Paths in the older files and in [`../findings-log.md`](../findings-log.md) may
still read `docs/power/<name>.txt`; the captures moved here on 2026-08-19 when
`docs/power/` was cut back to the current state of the device. The file names did
not change.

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

The loggers themselves (`powerlog-pmos.sh`, `powerlog-ut.sh`) are in the
[FP3 skills](https://github.com/llg179org/Claude-skills-Fairphone3) repository.

| file | what it holds |
|---|---|
| `2026-08-11_regs-pmos.txt`, `2026-08-11_regs-ut.txt` | the charger's CHGR, DCDC, BATIF, USB and MISC registers, 1280 of them, read on each OS with the same pack in the same state. 45 differed; `CHGR_CFG2` was the one that mattered |
| `2026-08-11_ut_discharge-charge.txt` | Ubuntu Touch: a night idle, a deliberate flash+camera load, then a full charge to termination |
| `2026-08-12_ut_terminates.txt` | the vendor stack reaching `TERMINATE` within a minute of the current crossing the threshold |
| `2026-08-12_pmos_iterm-fix-terminates.txt` | the same on pmOS, after `I_TERM_BIT` was left set — the single-change A/B |
| `2026-08-12_pmos_idle-discharge.txt` | pmOS idle, matched against the UT night |
| `2026-08-12_pmos_day-to-r51-termination.txt` | a day on pmOS ending in the first termination reached by the **packaged** kernel rather than by hand-deployed pieces: `linux-fp3-7.1.3-r51`, taper at 87 mA, then `Full` with `chgr_status_reg` at `0x45`. The uptime column resets partway through, at the reboot onto that package |
| `2026-08-13_pmos_camera-hold-idle-cost.txt` | the three-phase A/B/C above |
| `2026-08-13_pmos_ak7375-position-power.txt` | the same pair once more, with the driver patched so power follows the requested position: holding the subdev now costs 2.8 mA |
| `2026-08-13_pmos_lens-vs-chain.txt` | the follow-up three phases that split the hold: nothing held, the `ak7375` subdev alone, the rest of the chain without it |
| `2026-08-13_pmos_r52-charge-to-termination.txt` | a charge from 87 % to termination on `linux-fp3-7.1.3-r52`, over an SDP port (`usb_imax_uA` 500000, so ~340 mA into the pack). The taper crosses the threshold at **99.3 mA** and the charger is `Full` at `0x45` within the minute |
| `2026-08-14_pmos_rpm-sleep-stats.txt` | four `rtcwake` suspends of 60, 120, 300 and 600 s with the RPM sleep-stats, cluster genpd residency and the QG S3 witnesses read either side of each. The finding is that every RPM-level counter stays at zero |
| `2026-08-14_pmos_rpm-master-stats.txt` | the RPM per-master sleep records, read once the master-stats node and driver were in place. APSS has a shutdown count of zero; the modem and WLAN are in the hundreds |
| `2026-08-14_pmos_resume-early-rest-anchor.txt` | a 300 s `rtcwake` suspend with the [parked](../../../charger/bringup/parked/README.md) `.resume_early` patch applied: the anchor fires and moves the reading 93.87 % → 91.00 % off a rested OCV. Kept because it is the evidence that the parked patch works, not that it ships |

