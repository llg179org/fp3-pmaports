# 2026-09-06 — the touch stall localised to the slave (#179, r86 → r87)

Three releases in one morning. What each one measured, and the raw logs it
rests on. Narrative in `docs/touch/142-i2c-stall.md` §11–13; one-paragraph
summary in `docs/power/bringup/findings-log.md`.

## What is here

| file | what it is |
|---|---|
| `kernel-log-r86-boot.txt` | the r86 boot (08:02–09:35): three timeouts, the runtime-PM experiment and its refutation |
| `kernel-log-r87-boot.txt` | the r87 boot from 09:35: probe, bus numbering, and the first decode carrying the core registers |
| `r86-experiment.log` | the runtime-PM experiment's own before/after record, written on the device |

## The three results

**r86 (`debug-int/7.1.3` `585a3423b76f`) — the bus-clear is accepted now.**
r84's clear failed 3/3 because the core refused the write (`BUS_CLR` read back
`0x1` after ten attempts). r86 resets the core first. Same fault, same status
word `0x0411a700`, and:

```
09:00:23.817467  transfer to 0x48 timed out, ... SDA 1 SCL 0 (I2C_STATUS 0x0411a700)
09:00:23.819568  bus cleared after 1 attempt(s)
```

☠️ The tap was still lost. The transfer times out first, and 2.03 s during PIN
entry swallows several taps. This closes the cascade, not the fault.

**The refutation.** The hanging transfer followed a runtime-PM resume, which
pointed at the pinctrl cycling added for the speaker amp's bus. Disproved by the
experiment it proposed — with runtime PM off, no suspend and no resume, the
fault arrived anyway (09:08:48, same status word). ☠️ The observation was
**vacuous**: in `auto` the bus suspends after every transfer, so every transfer
is the first after a resume.

**r87 (`debug-int/7.1.3` `0347772e8544`) — which side is at fault.**

```
09:36:30.873297  transfer to 0x48 timed out, bus active, master is us, SDA 1 SCL 0
                 (I2C_STATUS 0x0411a700 STATE 0x0000001d OPER 0x00000010 ERR 0x00000000)
```

`QUP_STATE 0x1d` = RUN, `QUP_STATE_VALID` set. `QUP_ERROR_FLAGS 0x00` = none.
`QUP_OPERATIONAL 0x10` = `QUP_OUT_NOT_EMPTY`, bytes still unsent. **A master
waiting on the bus, not one that has stopped** — the himax holds SCL for over
two seconds and the QUP is correct throughout.

☠️ **It does not need a finger.** That event is 38 s into a boot with **one**
touch interrupt in the whole boot (`grep hx83112b /proc/interrupts`, located by
name). Every earlier capture came during heavy use because that is when anyone
was looking.

## Two things this capture also settles cheaply

- The bus is not overclocked: `using default clock-frequency 100000` for both
  `78b7000` and `7af6000`, read off the device rather than from the DTS.
- ☠️ The bus number **moved from i2c-4 to i2c-2** across the r87 reboot
  (`2-0048`). Nothing may hardcode it.

## What is NOT established

Why the controller is not ready. A low-power state the driver never wakes it
from, its own init after a panel power transition (panel and touch are both
HX83112B and share `iovcc` on `pm8953_l6`), and a crashed controller all fit the
evidence equally. The mainline read path is a bare `regmap_raw_read` on the
event stack with no wake, no handshake and no readiness check.

## How to reproduce the measurement

There is no reproducer for this fault — the 2026-09-04 unbind trigger makes a
different one (unpowered clamp, `SDA 0 SCL 0`). It arrives on its own; the
instruments catch it:

```sh
fp3-ssh 'sudo -n journalctl -k -b -o short-precise | grep -E "timed out, bus|bus cleared|SCREEN"'
fp3-ssh 'systemctl is-active fp3-i2c-qup-dyndbg fp3-screen-mark'   # both must be up
```

`bus cleared after` is a `dev_dbg`: without `fp3-i2c-qup-dyndbg.service` (which
re-enables the control file each boot) it does not appear, and its absence then
means nothing.
