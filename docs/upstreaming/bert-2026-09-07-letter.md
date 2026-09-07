<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# Bert Karwatzki's test report, 2026-09-07 — what it settles and what we may cite

He ran `integration/7.1.3` at `5bc4d5ebb7c0` on his own Fairphone 3 with Debian
trixie userspace, plus two local patches. Four findings, each landing on an open
item. **The letter is private mail to us**, which matters for what we may put in
a trailer — see the last section.

## 1. Call audio works — third-party confirmation of `wcd9335-audio`

*"Congratulation to you (and Claude ;-)). Call audio works great!"* — an
independent run of the audio series on different hardware and a different
userspace. This is the evidence `#152` was waiting for.

☠️ **It is not yet a `Tested-by:`.** That tag needs the person's **explicit
permission** (`submitting-patches.rst` §"Tagging people requires permission"),
and "it works" is a report, not a grant. The next mail has to ask.

## 2. There are two rear-camera hardware variants, and ours is not his

His FP3 has the **`lc898127` actuator** and the **imx363 at `0x10`**, not `0x1a`
— he had to disable our camera node entirely to boot. He also found the actuator
needs **two regulators**: without `vio` the i2c transactions time out, because by
the time the actuator probes, the sensor has already powered down.

That is a measured argument for splitting the board DTS into a common
`.dtsi` plus per-variant device trees, which is `#140`'s territory and until now
rested on our own reasoning alone.

★ **His `lc898217` patch is citable and reusable**, and he signed it off:
`Signed-off-by: Bert Karwatzki <spasswolf@web.de>` on
`8dc38ed9807f` (his tree). If any of it is taken, the rules are the skill's
import rules: bring it in **as his commit, authorship preserved** (`git commit
--author`, his `Signed-off-by:` kept), in a commit of its own, and put our
changes in a second one. `Co-developed-by:` is only correct if it is
**immediately followed by his own `Signed-off-by:`** — so it too needs him.

## 3. `1ac2e21fbf3a` breaks his touchscreen — the same signature as ours

```
Himax-hx83112b-TS 0-0048: Failed to read input event: -110
Himax-hx83112b-TS 0-0048: Failed to read input event: -6
```

after resume from suspend, and reverting the commit fixes it. That is `#142`, and
it is **byte-for-byte the cascade signature** this port measured on r82 — a
`-110` followed by a `-6` — which we closed as no longer cascading on r88
([`../power/bringup/captures/2026-09-06_179-no-cascade-on-r88/`](../power/bringup/captures/2026-09-06_179-no-cascade-on-r88/)).

☠️ Two different things share that signature and must not be conflated: **his** is
a regression introduced by the `system-pc` affinity commit and cured by reverting
it; **ours** was a bus fault whose cascade the i2c-qup recovery removed. Whether
our r88 recovery also masks his regression is **untested** — and worth testing,
because if it does, the affinity patch may be sendable after all.

## 4. ★ His unwanted wakeups are our unexplained loose end

His point 4: *"a lot of unwanted wakeups (especially with mobile data enabled).
The time between those unwanted wakeups is a few seconds up to an hour"*, and in
the linked thread: *"If I simply set all the smd irqs as `IRQF_NO_SUSPEND`, I get
spurious wakeups every 2 seconds."*

That is exactly what this port measured on 2026-09-07 and could not explain:
`rtcwake` asked for 720 s and the phone resumed after **4 s** and **110 s**, with
`/sys/kernel/debug/wakeup_sources` naming nothing
([`../power/bringup/captures/2026-09-06_182-modem-lost-on-resume/`](../power/bringup/captures/2026-09-06_182-modem-lost-on-resume/)).
**Two independent observers, same platform, same behaviour.** It stops being our
instrument misbehaving and becomes a property of the platform.

☠️ It does **not** explain the fault we were chasing. His topic is *unwanted*
wakeups; ours is the modem vanishing from ModemManager after a *wanted* one. Same
subsystem, different failure.

### And our own series is the upstream-shaped answer to his hack

He links [ModemManager work item
#694](https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/work_items/694),
"RFC: QRTR wake on SMS/Call support", where his patch marks SMD channels
wakeup-capable, sets `IRQF_NO_SUSPEND` on the SMD edge IRQ, and wakes on
`src_port == 39` (voice) or `52` (SMS, from `qrtr-lookup`).

☠️ **We have measured that port 52 is DSD on our firmware** (2026-08-30), not
wireless messaging — so the `qrtr-lookup` numbers are per-firmware, which
confirms his own caveat *"I don't know if the port numbers are universal"*. That
answer is queued as `#154`.

`upstreaming/qcom-smd-wake` is our version of the same idea and deliberately
avoids both hacks: the filter stays in **user space** and it uses a **wake IRQ**
instead of a blanket `IRQF_NO_SUSPEND`. So #694 is prior art for a series we
already carry, and it should be cited in its cover letter.

★ **Verified citation** (fetched 2026-09-07, `t.mbox.gz` → HTTP 200, a bogus
message-id → 404): Caleb Connolly's original,
`https://lore.kernel.org/all/20230117142414.983946-1-caleb.connolly@linaro.org/`,
*"[PATCH] rpmsg: qcom: glink: support waking up on channel rx"*.

## ☠️ What we may and may not write with his name

`submitting-patches.rst` §"Tagging people requires permission": every trailer
naming a person except `Cc:`, `Reported-by:` and `Suggested-by:` needs **explicit
permission** — and those three are implicit **only if** the person contributed
under that name and address per lore or the commit history, **and** did the
reporting or suggestion **in public**.

| | |
|---|---|
| name/address established? | ✅ **yes** — `git log --all` in the kernel tree shows **14 commits** by `Bert Karwatzki <spasswolf@web.de>` |
| was the report public? | ❌ **no** — it is private mail to us |

So:

- ☠️ **`Tested-by:` for the audio series — ASK.** Explicit permission required
  regardless of where the report was made.
- ☠️ **`Reported-by:` for the touchscreen regression — ASK.** The implicit
  permission does not apply to a report made privately, and the absence of a
  public `Closes:` target is the signal that it does not.
- ✅ **His public GitLab comments and his lore-archived patches may be cited**
  as `Link:` without asking — citing is not tagging.
- ✅ **His `lc898217` patch may be imported** with authorship preserved, because
  he published it with his own `Signed-off-by:` in the letter; a
  `Co-developed-by:` variant still needs his sign-off on our version.
