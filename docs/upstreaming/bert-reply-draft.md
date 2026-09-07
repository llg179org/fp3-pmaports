<!-- AI-generated draft (Claude Opus 5) under the direction of Lajosházi, László
     Gergely. NOT SENT - the operator sends it, and it is written to be sent as
     his own words. Date it on the day it goes out. -->

# Draft reply to Bert Karwatzki — `#154`, and the answer to his point 3

**Status: draft, unsent.** It asks for three permissions, which is the whole
reason it exists (`#152`, `#154`, and the `lc898217` import).

---

Hi Bert,

thank you — an independent run on a second Fairphone 3, with a different
userspace, is worth more than anything we can measure here alone. Four answers
and three questions.

## 1. The touchscreen — please test the branch tip, not the revert

Your bisect is correct and the commit really is in your tree, but I think it is
the *trigger* rather than the fault, and the fix already exists — it just landed
after the commit you tested.

You ran `integration/7.1.3` at `5bc4d5ebb7c0`, which is dated **2026-08-30**.
The touch path had no protection at all at that point. These four came later:

```
cd2745d8d321  2026-09-04  Input: himax_hx83112b - hold the rails the touch half runs on
c508e99b9fa9  2026-09-04  arm64: dts: qcom: sdm632-fairphone-fp3: give the touchscreen its supplies
fb68b1bd764f  2026-09-05  Input: himax_hx83112b - retry a failed event read, and rate-limit the error
58f135a76e46  2026-09-05  Input: himax_hx83112b - do not let a failing read disable the interrupt
```

The first two are the ones that matter, and they were written for exactly your
`-110` → `-6`. What we measured here, out of the kernel's own regulator
framework and with no build or flash:

```
screen ON    l6   use=1   ->  1a94000.dsi.0-iovcc   use=1
screen OFF   l6   use=0   ->  1a94000.dsi.0-iovcc   use=0
```

`pm8953_l6` had **exactly one consumer**, the display half's `iovcc`, and it
drops its vote when the panel is powered down. These hx83112b parts are TDDI —
one die drives display and touch — so the touch controller was running on a rail
it did not hold and could not see released. When the rail goes, the next transfer
holds both lines low until the QUP transfer timeout expires (14.98 s on this
board) and the driver reports `-ETIMEDOUT`, then `-ENXIO`.

The reason the binding could not carry the supply is worth knowing if you look
at this yourself: the touch half was under `trivial-touch.yaml`, which has
`unevaluatedProperties: false` and cannot describe a regulator at all. So the fix
is three patches to three trees — a binding of its own, the driver taking the
supplies, and the DTS naming them.

**The ask:** could you run the current `integration/7.1.3` tip *without* your
revert? If the four commits above make it go away, the affinity change is
sendable and your revert is masking rather than fixing.

### ☠️ And the part I cannot explain, so I will not pretend otherwise

On **our** phone this fault does not need a suspend at all. We caught it twice in
one session, 324 s and then 47.6 s after a resume, with no sleep in between; what
predicts it is **screen off** plus **≥10 s of touch idle**, and an interleaved
A/B gave 5/5 failures with the screen off against 0/5 with it on. There is even a
clean boot here on `0x42000353` with a real suspend/resume and ~513 post-resume
touch interrupts and no `-110` at all.

So I have no mechanism by which reverting the affinity change should cure it, and
I would rather say that than invent one. If the tip still fails for you, that is
a real second fault and I would very much like to know.

**A one-line check, if you have a minute** — with your display on and then
blanked:

```sh
cat /sys/kernel/debug/regulator/regulator_summary | grep -A3 -w l6
```

If `l6` loses its last consumer when the screen blanks on your device too, we are
looking at the same thing.

## 2. `qrtr-lookup` port numbers are per-firmware — your caveat was right

You wrote *"I don't know if the port numbers are universal"*. They are not. On
our firmware **port 52 is DSD, not wireless messaging** (measured 2026-08-30), so
a wake filter keyed on 39/52 would wake on the wrong service here.

That is why our `qcom-smd-wake` work keeps the filter in **user space** and uses
a **wake IRQ** rather than a blanket `IRQF_NO_SUSPEND` — your own note that
`IRQF_NO_SUSPEND` on all the smd irqs gives spurious wakeups every 2 seconds is
the argument against the blanket form, and it is your observation, not ours.

Your [MM work item #694](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/work_items/694)
is prior art for that series and will be cited in its cover letter, alongside
Caleb Connolly's
[`rpmsg: qcom: glink: support waking up on channel rx`](https://lore.kernel.org/all/20230117142414.983946-1-caleb.connolly@linaro.org/).

## 3. Unwanted wakeups — independently seen here

Your *"a few seconds up to an hour"* matches something we measured and could not
explain: `rtcwake` asked for 720 s and the phone came back after **4 s** and, in
another cycle, **110 s**, with `/sys/kernel/debug/wakeup_sources` naming nothing.
Two observers on the same platform makes it a property of the platform rather
than one of our instruments, which is genuinely useful to know.

## 4. Two rear-camera variants — your report changed our plan

`lc898127` with the imx363 at `0x10`, against `lc898217` and `0x1a` here, is a
measured argument for splitting the board DTS into a common `.dtsi` plus
per-variant device trees. That was our own reasoning alone until your mail.

Your point that the actuator needs `vio` as well, because the sensor has already
powered down by the time it probes, is the kind of thing that is invisible until
someone with the other variant tries it.

## The three questions

1. **`Tested-by:`** on the wcd9335 audio series — may we add
   `Tested-by: Bert Karwatzki <spasswolf@web.de>`? You reported it privately, and
   the kernel's `submitting-patches.rst` says a tag naming a person needs their
   explicit permission, so I am asking rather than assuming.
2. **`Reported-by:`** on the touchscreen work — same question. The implicit
   permission in that document applies only to a report made **in public**, and
   yours was mail to us.
3. **Your `lc898217` patch** (`8dc38ed9807f`, with your `Signed-off-by:`) — may
   we carry it? It would go in as **your** commit with authorship preserved and
   your sign-off intact, with anything we change on top in a separate commit.
   `Co-developed-by:` would need a sign-off from you on our version, so it is
   only worth doing if you would prefer that shape.

Also, if you would rather be `Cc:`'d on the series than tagged, say so and we
will do that instead.

Thanks again,

Laci

---

## ☠️ Notes for the sender, not for Bert

- The four commit hashes are `integration/7.1.3` twins, which is the branch he
  runs. Do not paste the `wip/7.1.3/touch` hashes (`a316c7edd163`,
  `71e8b167175c`, `18483b7410a7`) — they are the same changes on a branch he
  does not have.
- Every measurement quoted is in
  [`../power/bringup/captures/2026-09-04_142-touch-after-resume/`](../power/bringup/captures/2026-09-04_142-touch-after-resume/)
  and [`../power/bringup/captures/2026-09-07_142-affinity-vs-touch-after-resume/`](../power/bringup/captures/2026-09-07_142-affinity-vs-touch-after-resume/).
- ☠️ Nothing here claims his revert is wrong or that the tip fixes him. It says
  what we measured, what we cannot explain, and asks him to test. Do not
  strengthen it before sending.
- **Not asked, deliberately**: whether he sees the phoc DSI resume failure
  (`#183`). He runs Debian trixie, not phosh, so his answer would not be
  comparable; ask a phosh user instead.
