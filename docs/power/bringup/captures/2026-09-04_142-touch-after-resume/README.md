# 2026-09-04 — #142, Bert Karwatzki's hx83112b touch-after-resume regression

**Incomplete. One arm of two, and its result is not yet evidence.** Read the
caveat before quoting anything here.

## The question

`0314fee3ce35` ("arm64: dts: qcom: msm8953: name the right affinity level for
system-pc") moves `system_pc`'s `arm,psci-suspend-param` from `0x41000353` to
`0x42000353` (affinity level 1 → 2). Bert Karwatzki reports (mail 2026-09-03)
that on **his** FP3 this breaks the hx83112b touchscreen after resume, with i2c
`-110`/`-6`, and that reverting the commit fixes it. Does it reproduce on ours?

Protocol pre-registered 2026-09-04 in
[`../../findings-log.md`](../../findings-log.md) before any data existed.

## Device and build

```
kernel   #80-fp3 SMP PREEMPT Sat Aug 29 08:52:09 UTC 2026     (pkgrel 79)
_commit  5aafd59e553ae5385f4e44f5d8b5846c3179bd7c             (from /usr/share/kernel/fp3/fp3-commit)
dtb      /boot/dtbs/qcom/sdm632-fairphone-fp3.dtb  md5 3181f573680e32a02ff6144ff2f59c9c
```

☠️ The installed kernel is **not** the package's pinned `_commit`
(`b8023520cddb`, r80) — built and pinned is not installed. Every number here
belongs to `5aafd59e553a`.

**Baseline control for arm A**: the same board dtb built on the host from that
exact commit with the package config is `3181f573680e32a02ff6144ff2f59c9c` —
**byte-identical to the deployed one**. So a reverted dtb built the same way
will differ from what is running by exactly the one property, and by nothing
else. (Built with `make ARCH=arm64 CC=gcc HOSTCC=gcc qcom/sdm632-fairphone-fp3.dtb`
in a worktree detached at `5aafd59e553a`.) This is the check that stops a
category-branch dtb, or a tip-of-`debug-int` dtb, being deployed as if it were
the same thing — the tip is 10 commits ahead and now also carries the rear-camera
overlay split.

## Files

| file | what it is |
|---|---|
| `armB-suspect-0x42000353.txt` | the suspect arm, as deployed. Raw output of the capture script |
| `142-arm.sh` | the capture script, byte-identical to what ran on the device (sha256 `5df7eff1…`), syntax-checked with the device's own `busybox ash` |

## Arm B — the suspect value, measured 2026-09-04 11:15

```
system-pc param        = 42000353        (read back from the live DT during the run)
suspend_success 186 → 187   delta=1   rtcwake_rc=0
PM: suspend entry (s2idle) … PM: suspend exit    (both edges inside our own kmsg markers)
i2c / hx83112b errors in the window: 0
input4 (hx83112b) still present
```

The phone did suspend and resume — the counter delta and the entry/exit pair
both say so, and the window is bounded at both ends by markers written from
inside the run.

## ☠️ Why the zero is not a result

```
137:  0 0 0 0 0 0 0 0  msmgpio 65 Level  hx83112b
```

The touch IRQ is at **zero for the whole boot**, and the display was `dpms Off`.
Nobody has touched the screen since 23:16 the previous evening, so nothing has
asked the controller for anything. Bert's symptom is an i2c error *on access*;
with no access there is nothing to fail. **"No i2c error" here measures that we
did not try, not that touch works.**

That is the same trap as "a clean log proves nothing until the channel is shown
to report that event class at all". The arm is therefore only half-run: the
machine half is done, the half that exercises the controller needs a human
touching the panel, which is a Step-4h action — one at a time, on an explicit
confirmation, never on a timer.

## What is still owed

1. **Pre-suspend touch baseline** (human): touch the panel, confirm the IRQ
   counter leaves zero. Without it, a dead touch after resume cannot be
   distinguished from touch never having worked this boot — the outcome the
   pre-registration names as voiding the comparison.
2. **Arm B, second half** (human): suspend again, then touch again; read the IRQ
   counter and the i2c errors.
3. **Arm A**: deploy the reverted dtb (one property, `0x41000353`), built from
   `5aafd59e553a` against the proven-identical baseline above, and repeat 1–2.
4. Only then does the pass/fail in the pre-registration apply.

☠️ And the limit that holds whatever we find: Bert's report is on a **second**
FP3. A clean run here does not disprove it — two devices differing is itself the
finding, and the question would move to what differs between them.

---

## Update, same day: the reproduction, and the control it still lacked

`armB-first-touch-after-resume.txt` carries it. The one `-110` of the whole boot
landed on the **first touch access after the resume** — Bert's error code in
Bert's position in the sequence.

☠️ **Reading the timestamps needed a correction that inverts the conclusion.**
The printk clock stops across suspend while `/proc/uptime` counts suspended time,
so `boot_wall + dmesg_ts` put the event at 09:30 — two hours before the operator
touched anything, which reads as "unrelated to us". Anchoring the monotonic clock
from inside the run (`kt 37054.47 = wall 11:26:49`) puts it at **11:22:59**, in
the operator's own touch session, 7.5 min after the resume. Anchor the clock; do
not compute wall time from boot plus a dmesg timestamp on a machine that sleeps.

What the arm still lacked, and why the phone was rebooted at 11:30: **no control**.
Nothing showed whether the first touch of a boot that has *never suspended* also
produces a `-110`. Without that, "it happens after resume" and "it happens on the
first access of a boot" are the same observation.

Fresh boot 2026-09-04 11:30:53, same kernel and same `system-pc = 0x42000353`:

```
uptime 39 s   suspends 0   touch IRQ 0   -110 count 0
grep pattern self-test on a synthetic line: 1   (the pattern can fire)
```

That is the clean baseline the control needs. Awaiting the operator's first touch
on a boot with zero suspends.

---

## Trial 2, and what it does to the plan

Clean boot, same `system-pc = 0x42000353`, one suspend/resume (resume 11:35:53),
~513 post-resume touch interrupts: **no `-110`**.

| trial | boot state before the touch | suspends | `-110` |
|---|---|---|---|
| 1 | 12 h uptime, boot of 23:16 | 187 | **1**, on the first touch after resume |
| control | fresh boot, never suspended | 0 | 0 |
| 2 | fresh boot, one suspend | 1 | 0 |

**One event in two suspend→touch trials**, and the one positive sits on a boot
that differs from the negative in almost everything except the DT property: 12
hours of uptime and 187 accumulated suspends against 39 seconds and one.

☠️ **This is what the A/B cannot survive as designed.** A single trial per arm
distinguishes nothing when the event is not produced by every resume: an arm A
that comes back clean would be indistinguishable from an arm B that came back
clean, which it just did. The rate has to be known before the revert means
anything — the same trap this port already paid for once, where six consistent
samples read as a null result and the same configuration later spread over an
order of magnitude.

☠️ **And the measurement is human-rate-limited.** The `-110` arises when the
driver takes a touch interrupt and then fails the i2c read, so every trial needs
a physical touch; it cannot be driven from the host. That is a hard constraint on
how many trials are affordable, and it belongs in the plan rather than being
discovered halfway through it.

Open, in order:
1. how often does it happen per resume, in the regime where it was seen at all
   (long uptime, many suspends)?
2. only then: the same protocol with `0x41000353`.
