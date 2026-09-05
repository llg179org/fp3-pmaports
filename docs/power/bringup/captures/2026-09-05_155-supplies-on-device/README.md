# #155 on the device: the touch half now holds its own rails

2026-09-05, kernel `linux-fp3-7.1.3-r81`, `uname -v #82-fp3`, source commit
`3f843d0534e3` (`debug-int/7.1.3`), pmOS on slot_b. Identity green
(`fp3-selftest --only identity`: build stamp, installed package and source
commit all agree with the pin), so the measurements below are on the kernel
that carries the fix and on nothing else.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the change and the measurements.

## ☠️ First: the verification step #155 asked for cannot work

#155 says "then re-run `142-trigger.sh`". That reproducer **unbinds the touch
driver** before probing, and the fix holds its supplies with
`devm_regulator_bulk_get_enable`, which releases them on unbind. So on a fixed
kernel the reproducer recreates the *pre-fix* rail state, and a stall there
would say nothing about the fix either way.

That is not an argument, it is measured — `155-unbind-rails.sh`, screen ON
throughout (the only state the rebind works in), raw output in
`155u-raw.txt`:

| | `l6` use | `l6` consumers | `l10` use |
|---|---|---|---|
| driver **bound** | 2 | `3-0048-iovcc`, `1a94000.dsi.0-iovcc` | 1 (`3-0048-vdda`) |
| driver **unbound** | 1 | `1a94000.dsi.0-iovcc` only | **0** (no consumer) |
| driver **rebound** | 2 | both again | 1 |

Unbound is exactly the broken kernel's rail state: `l6` held only by the panel,
`l10` unvoted. Running `142-trigger.sh` here would measure the old bug on the
new kernel. It was therefore **not** run, and the record says so rather than
quietly substituting a different test.

## The measurement that does test the fix

The same instrument the root cause was found with — `regulator_summary`, screen
toggled over the phosh ScreenSaver interface — but with the driver **bound**,
which is the state the operator's fault happens in. `155-rails-bound.sh`, raw
output in `155-raw.txt`, arms run ON → OFF → ON so the return is visible.

The control is not a fresh reading: it is the pre-fix measurement recorded on
2026-09-04 in
[`../2026-09-04_142-touch-after-resume/ROOTCAUSE-the-panel-owns-the-rail.md`](../2026-09-04_142-touch-after-resume/ROOTCAUSE-the-panel-owns-the-rail.md),
taken on a different day, on the previous kernel, by a different run.

| | pre-fix, 2026-09-04 | r81, 2026-09-05 |
|---|---|---|
| screen ON, `l6` use | 1 — only `1a94000.dsi.0-iovcc` | **2** — `3-0048-iovcc` **and** `1a94000.dsi.0-iovcc` |
| screen OFF, `l6` use | **0** — the panel released it and nobody else voted | **1** — `1a94000.dsi.0-iovcc` drops to 0, `3-0048-iovcc` stays at 1 |
| `l10` use, either state | 0, no consumer at all | **1** — `3-0048-vdda`, in both states |
| screen ON again | — | back to 2, i.e. the arms are reversible |

**The rail the touch controller runs on no longer loses every voter when the
display goes down.** That is the mechanism the fix was written for, and it is
now the measured behaviour rather than a claim about the source.

## ☠️ What this does NOT establish

It does not show the operator-visible fault is gone. That fault is
`Failed to read input event: -110` on a *first access after an idle*, with the
driver bound, during ordinary use — and the rate is per vulnerable moment, not
per transaction: 15 stalls in a 50-minute session of real tapping, gaps between
them of 23 s to 726 s. So a clean run shorter than a few times 726 s can come
back empty while the fault is fully present, which makes the shortest credible
active run about 36 minutes of real use with pauses. See the reasoning in
`fp3-pmaports/tests/checks/59-touch-i2c-stall-test.sh`.

Nothing here substitutes for that. `59-touch-i2c-stall` reports it passively on
every later selftest run, and says explicitly when it is measuring "nobody
touched the screen" rather than "no stalls" — that check, on a day of ordinary
use, is the confirmation still outstanding.

## Commands

```sh
fp3-selftest --only identity                      # which kernel this is
sudo sh 155-rails-bound.sh                        # the bound screen A/B
sudo sh 155-unbind-rails.sh                       # what unbind does to the rails
```

☠️ Both scripts end with `; true)` inside the device-lookup command
substitution. Without it, `set -e` kills the script with **no output on either
stream**: the `for` loop's last iteration is a non-matching device, so the loop
exits non-zero, the substitution inherits that, and the assignment fails. That
happened here first time out — rc=1, both files empty — and an empty capture is
the easiest thing in the world to read as "nothing to report".
