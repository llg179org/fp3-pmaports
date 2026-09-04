# Paused 2026-09-04 13:22, to resume at the weekend

The runtime-PM experiment was **armed and then disarmed unused**. Nothing about
it has been measured; do not read the absence of `-110` after 13:21 as a result.

## ☠️ Why it was disarmed rather than left running

Two things were live on the device that would have corrupted the power lane's
own measurements, and both were mine:

- **`78b7000.i2c power/control = on`** holds an i2c controller out of runtime
  suspend permanently. The device spends 82 % of its time with that controller
  suspended, so pinning it awake changes idle power — and #85 (the overnight
  replication) and #79 (shunt calibration, 10:24) are power measurements on this
  same phone.
- **Three 1 Hz loggers.** The ledger alone costs ~60 ms of every second (6 % duty,
  most of it `dmesg | grep`). That is a load, not an observer, on anything
  measuring milliamps.

Neither would have announced itself in the power capture. They would simply have
shifted the numbers, on a night whose bands were pre-registered — the exact shape
of "a confound an order of magnitude larger than the effect", introduced by the
person measuring something else.

State restored: `control=auto`, controller `suspended`, all three units
`inactive`. A `FP3-142-DISARM` marker is in the kernel log.

## What the weekend run has to do

The hypothesis is unchanged and untested: **the transaction that hangs is the
first one after a runtime resume.** The controller autosuspends after 1 s idle,
so ordinary use suspends and resumes it constantly.

```sh
# 1. restart the instruments (scripts are already on the device, in /home/fp3)
sudo systemd-run --unit=fp3-142-evcount --collect /usr/bin/python3 /home/fp3/142-evcount.py
sudo systemd-run --unit=fp3-142-ledger  --collect /bin/sh      /home/fp3/142-touchlog2.sh
sudo systemd-run --unit=fp3-142-gaps    --collect /usr/bin/python3 /home/fp3/142-gaps.py

# 2. BASELINE arm first, control=auto (as shipped). Touch for N minutes, note N.
#    Read: dmesg | grep -c -e "Failed to read input event: -110"

# 3. Then the test arm:
echo on > /sys/devices/platform/soc@0/78b7000.i2c/power/control
#    Touch for the SAME N minutes. Read the same counter.

# 4. Disarm afterwards, every time:
echo auto > /sys/devices/platform/soc@0/78b7000.i2c/power/control
```

☠️ **The arms must carry comparable touching.** The `-110` rate is
usage-driven, not time-driven: measured 2026-09-04, ~30 errors in ~2 h of active
use and ~13 000 frames, i.e. roughly one per minute of tapping — while two
unattended boots the day before produced **zero**. A clean test arm proves
nothing unless it saw as much touching as the baseline. Minutes, not seconds.

## Where the question stands

The operator asked what change breaks the touch. Measured answer so far:

- **Not new**: boot -4 (2026-09-03, 8 h) already had 26 of these errors, on the
  same kernel, before any of this work.
- **Usage-driven**: boots with no human interaction had zero.
- **Not our pinctrl fix's absence**: `pinctrl_pm_select_sleep_state` is present in
  the running kernel, and that fix targets BLSP6 anyway; the touchscreen is on
  BLSP3 (`78b7000`).
- **Not `0314fee3ce35`**: 15 events, not one of them needed a suspend.
- **Whether it is a regression at all is unknown** — every boot the journal still
  holds is the same kernel `#80-fp3`. The extlinux fallback entries `r77`/`r78`
  are the way to answer that, at the cost of a reboot and another manual session.
