# The frame for the next autonomous run — how this reaches the halving

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

**GOAL (unchanged):** halve pmOS idle consumption — to the oracle's level or
below — **at the oracle's responsiveness**, i.e. a call still wakes and rings the
phone.

This page exists because the goal has been pursued through a dozen levers and the
run kept losing the thread between them. It states, once: what the target
arithmetic actually demands, which of the two tracks each number belongs to,
which levers are **already spent and must not be re-run**, and what the next
autonomous run does in what order with **the decision rule written before the
measurement**.

Read `bringup/tools/prior-art.sh <counter-or-field>` before measuring anything.
It exists because a closed result was re-derived and written up as new.

---

## 1. The arithmetic decides the shape of the work

The measured model, both systems on one line
(`STATUS.md`, `2026-08-28_2gonly-master-ab/`):

```
current [mA] = 54.9 + 135.0 × MPSS-duty
```

| row | number | where it comes from |
|---|---|---|
| pmOS LTE idle | **98.5 mA** (duty 34.8 %) | measured, two-sided A-B-A′ |
| oracle LTE idle | **~63 mA** (duty 6.1 %) | measured on slot_a, same cell, same firmware |
| **parity** target | 55–64 mA | the oracle's own `cc_soc` band |
| **halving** target | **≤ 50 mA** | the user's goal |

☠️ **The halving is below the model's 54.9 mA intercept.** That is the single
most consequential fact on this page, and it forces the split:

| track | what it buys | ceiling |
|---|---|---|
| **D — modem duty** (34.8 % → 6.1 %) | 98.5 → **63 mA** *awake* | parity while awake |
| **R — suspend** (the phone actually asleep, for real spans) | removes the 54.9 mA intercept | see below — **not** what it was thought to be |

### ☠️☠️ The split above was rewritten 2026-08-31, and the tracks turned out to be one

The paragraph that stood here said *"track D is necessary and insufficient; track
R is where the goal is won."* **Step 0 falsified it.** Measured over 10.02 h, 58
consecutive 602 s suspends, all ending on the RTC alarm, 96.8 % asleep:

```
floor_mA = 48 ± 5 mA          (fit 45.5 → 51.0 as the flat top is cut back)
```

and the model's modem term at this phone's duty is `135.0 × 0.348 = 47.0 mA`.

⇒ **Suspend removes the 54.9 mA AP term almost exactly and leaves the modem term
untouched.** Track R does not reach *under* the intercept — it reaches *the modem*,
and stops there. Substituting into `night_mA = (1−r)·98.5 + r·floor_mA`:

| `floor_mA` | sleep fraction needed for 50 mA |
|---|---|
| 45.5 | 91.5 % |
| 48.0 | 96.0 % |
| 51.0 | **unreachable** |

So the honest statement is the opposite of the old one: **track R is already
bought — the AP term goes away for free the moment the phone sleeps — and after
that only the MPSS duty is left.** The two tracks have collapsed onto one
quantity. Reaching ≤ 50 mA with any margin means moving 34.8 % toward 6.1 %,
which is **track D**, and specifically step D2.

☠️ Track R is not worthless: without residency the phone sits at 98.5 mA and no
duty reduction alone reaches 50 mA either (63 mA at the oracle's duty). **Both are
needed; neither is sufficient.** What changed is that R has no *remaining*
headroom to find — it is a policy question (does the phone sleep when idle?), not
a power question, and its ceiling is now a measured number rather than a hope.

Full derivation, with what it does not say:
[`bringup/what-sleeps-and-what-does-not.md`](bringup/what-sleeps-and-what-does-not.md).

---

## 2. What is already spent — do not re-run these

Every row measured, two-sided where the phrasing says A-B-A′.

| lever | verdict | evidence |
|---|---|---|
| PDP context / data bearer up on pmOS | ☠️ **flat** 35.0/36.0/36.8 % vs 34.8 % | `2026-08-28_bearer-master-ab/` |
| the IPA handshake ("it never completes") | ☠️ **completes** — five claims retracted | kprobe on `ipa_client_new_server` |
| modem firmware differs between the systems | ☠️ **identical** image on both slots | `QC_IMAGE_VERSION_STRING` |
| `mmcli --disable` | ☠️ duty unmoved (36/34/34 %) | — |
| `--set-power-state-low` | duty **0.0 %**, 57.5 mA — but ☠️ **the call is lost** | measured by dialling |
| radio off | 1802 s of a 1800 s window — ☠️ no calls by construction | `radio-off-sleep.sh` |
| 2G-only | 54.0 mA / 6.5 % — ☠️ an **instrument**, not a proposal | `2026-08-28_2gonly-master-ab/` |
| eDRX / PSM over QMI | ☠️ **blocked with reason**: modem answers `InvalidQmiCommand` | all three routes exhausted |
| ModemManager terse | call ✅ survives; residency verdict **withdrawn** (confound ≫ effect) | — |
| signal strength as the explanation | ☠️ points the wrong way — the oracle reads *weaker* | — |

**The standing conclusion under all of it:** LTE is not intrinsically expensive
on this hardware — the same modem, firmware and cell costs 6.1 % under the vendor
stack — and **the cheaper system is the one doing more**. The question is not what
pmOS holds up. It is what the vendor stack *sets up* that ours never does.

---

## 3. The ladder — in order, with the decision rule stated first

### Step 0 (track R, blocks everything) — **what does this phone draw while asleep?**


> ## ✅ ANSWERED 2026-08-31 — and it rewrote §1
>
> `floor_mA = 48 ± 5 mA`. 58 rounds of 602 s over 10.02 h, every one ending on
> `56:pm8xxx_rtc_alarm`, `suspend_stats` 14 → 71 with `fail=0`, 96.8 % asleep.
> Gates all held (ModemManager stopped, `bl_power=4`, `Discharging`) — they are
> hard `exit 1` checks, so the data existing proves it. `mem_sleep` is
> **`[s2idle]`** and `deep` is not offered, so there is no deeper state that was
> missed.
>
> ☠️ **The pre-registered decision table read `>40 mA ⇒ the AP is not really
> going down`. The number landed there and the reasoning is wrong.** That branch
> assumed a high floor could only mean a failed suspend; 58/58 succeeded. The
> floor is high because **the floor is the modem** — the model's modem term is
> 47.0 mA and the measurement is 48.
>
> Consequences are in §1 above and the derivation in
> [`bringup/what-sleeps-and-what-does-not.md`](bringup/what-sleeps-and-what-does-not.md).
> ☠️ The floor still contains the USB link, never measured in mA; that is now the
> single numeric weakness of the "the floor is the modem" claim.

Nothing else can be prioritised until this number exists. The goal's ≤50 mA row is
a *suspend* row, and it has never been measured on a system that could stay
asleep. It can be now: four consecutive 600 s windows were filled today.

- instrument: `bringup/tools/sleep-night.sh` + `sleep-night-fit.py`, preceded by
  `bringup/tools/awake-ocv-control.sh` — **the control leg, written 2026-08-30
  because it did not exist.** The fit prices a suspend from the rest-OCV slope,
  and that is a new instrument aimed at a regime nothing else can reach: exactly
  the shape that once produced a "spectacular sub-2 mA" reading. The control runs
  the identical sampling with the phone awake, where the ladder already says
  ~98.5 mA, in the same configuration (ModemManager stopped, panel down, charge
  input cut). **If the control does not reproduce the known number, the sleeping
  number is not a measurement and step 0 has not been done.**
- ☠️ gate: the pack must be **off the cable** — a charging leg makes `cur_mA` the
  charge current and its p10 read 0.0. That has already spoiled one capture.
  `sleep-night.sh` cuts the charge input itself and restores it on every exit
  path, so no separate pre-drain is needed.
- ☠️ **The `floor_pct` argument is a safety stop, not a finish line.** Measured
  2026-08-30: starting at 93 %, the cycle average is ~14 mA at a 10 mA floor and
  ~44 mA at a 40 mA one, so reaching the 55 % default takes **26–83 hours**. The
  fit reads whatever arc has accumulated; the control leg travelled 92.7 mV in
  1.42 h at ~122 mA, so the same travel asleep needs **4–17 h**. Plan to read it
  the next morning, not the same evening.

☠️ **What step 0 measures is a FLOOR, not a night.** `sleep-night.sh` refuses to
run with ModemManager up — *"this would measure the daemon, not the phone"* — and
it uses `rtcwake -m mem`, which goes straight to `/sys/power/state` and bypasses
logind. So the number it returns is what a suspend costs on a phone that **cannot
receive a call**, which is the opposite corner of the goal. It is still the right
first measurement, because it is the term the night average cannot go below.

The night the goal is actually about is

```
night_mA = (1 - r) x 98.5 + r x floor_mA
```

where `r` is the fraction of the night actually spent suspended **with the modem
subscribed and callable**. Step 0 gives `floor_mA`; the R-track gives `r`. Both
are needed before any lever can be priced, and neither exists today.

Worked, to show what is at stake: at a 10 mA floor, reaching ≤50 mA needs
`r ≥ 0.55`. At a 40 mA floor it needs `r ≥ 0.83`, and no arrangement of sleeps
that keeps a phone callable has come close to that here. **The floor decides
whether the residency work is worth doing at all**, which is why it blocks.

**Pre-registered reading:**

| suspend current | what it means | next step |
|---|---|---|
| **< 15 mA** | residency is the lever; the night average is (1−r)·98.5 + r·small | → step R1 |
| **> 40 mA** | the phone is not really going down — the AP never releases the crystal | → step X1, and **X1 becomes the whole goal** |
| between | both, and X1 first because it raises the ceiling of R | → X1 |

The prior evidence points at the second row and is not enough to skip the
measurement: across a real 601 s sleep `APSS` read `XO total duration: 0` with
`XO shutdown count: 0`. If the application processor never lets the crystal go
*while suspended*, suspending buys far less than the arithmetic assumes.

#### ☠️ What "without the cable" actually means here — added 2026-08-30

The run does **not** have the cable pulled. It sets the PMIC's `input_suspend`
bit, which cuts the charge input: measured this evening, the supply reads
`Discharging` for the duration and `Charging` once the run stops. Electrically
that is what unplugging would do, and it is what makes the current columns mean
anything.

**What it does not do is remove the USB link.** The PHY stays powered and the
CDC-NCM interface stays enumerated, deliberately — the cable *is* the remote
link, and the host cannot cut VBUS, so a real unplug would end unattended access
and with it the measurement.

⇒ **`floor_mA` therefore includes whatever the USB link costs**, and that term
has never been measured in mA. What *is* on record (`captures/2026-08-24_usb-controller-not-the-vlow-blocker.txt`)
is that the USB controller and its PHY do runtime-suspend, so the contamination
is plausibly small — but "plausibly small" is not a number, and it must be
written next to the result rather than assumed away. If step 0 lands in the
`15–40 mA` band, this is the first term to go and measure, because it could
decide which side of the decision table the phone is really on.

### ☠️ Step X1 as first written was already answered — corrected 2026-08-30

The first draft of this page sent the next run to "census the rails that never
vote sleep". **That is done and the answer is negative**, and it was negative
before this page was written: with the USB PHY unbound the census leaves
**exactly one** enabled rail with no sleep vote, and it is `ldoa/8`, the eMMC's
`sdhc_1:vmmc`, which has to stay up (`2026-08-19_rail-census-usb-off.txt`,
`leads/rpm-sleep-set.md`). The lead's own verdict: *"no patch on this page buys
any current on the FP3."*

Re-run today with USB attached, it reproduced the **five**-rail list — and the
2026-08-19 capture header had already predicted that in writing: *"three of the
five enabled rails are USB PHY rails. Repeat it on WiFi only before reading
anything into those three."* The delta against the 08-23 capture looked like a
finding for about a minute. It is the cable.

☠️ The failure that produced the wrong step: this page's X1 was written from a
one-line memory of the lead ("the real front: the RPM sleep set") without reading
the lead's closing section. **A file's headline is not its verdict.**

And the whole `vlow` family is spent on our side too: the AP-side sleep-set
variants, `xo_sleep_off`, `both_sets`, `sleep_init`, and a **powered-off ADSP**
all leave `vlow Count: 0`.

### ★ Step X1 (corrected) — the one control the lead itself says is unrun

> *"…which raises the prior on the one control still unrun, the oracle with USB
> detached: whether a working system ever reaches `vlow` on this SoC at all."*
> — `leads/rpm-sleep-set.md`

**Does the oracle ever reach `vlow`/`vmin`?** `bringup/tools/ut-vlow-idle.sh` is
the oracle half and `vlow-idle.sh` the pmOS control; both exist and neither has
been run as a pair.

**Pre-registered reading:**

| oracle `vlow Count` | meaning | consequence |
|---|---|---|
| **> 0** | a working system *does* reach it here, so our 0 is a defect with an address | the deep-sleep floor becomes a real, bounded target and X-track is worth a campaign |
| **0** | ☠️ **no system reaches `vlow` on this SoC** — the state is not available, and every hour spent chasing it is spent against a wall | **close the entire X-track** and put the halving's weight on residency (R) plus whatever D can give |

☠️ The comfortable outcome for a track already argued at length is the first.
The second is the one that saves the most time, and it must be as publishable as
the first.

**It shares a slot switch with step D1** — one reboot into slot_a answers both.
Run them in the same trip.

### ✅ ANSWERED 2026-08-30, and it closes the track

Both readings taken on slot_a the same afternoon
(`captures/2026-08-30_oracle-xo-and-deepstate/`):

- **The oracle's `APSS xo_count` is `0x0`** — as is
  `xo_accumulated_duration` and `xo_last_entered_at` — at 120 s and again at
  394 s of uptime, against `numshutdowns` of 3 112 and then 19 181. Every other
  master reports non-zero XO shutdowns, so the counter works. **pmOS reads
  exactly the same.** Parking the APSS XO vote cannot be what separates a 98.5 mA
  system from a 63 mA one, because the 63 mA one does not do it either.
- **The `vlow` question has no oracle.** The downstream 4.9 kernel does not build
  `rpm_stats.c`, so that side has no `vlow`/`vmin` counter at all. There is no
  same-instrument comparison to be had, and substituting `lpm_stats`'
  `system-pc` — a cpuidle counter, not an RPM voltage corner — would be the
  two-witnesses-at-different-layers mistake this project has already paid for
  once.

**Consequence for the frame:** the ≤50 mA row cannot be reached by making the
RPM or the APSS vote differently, and this morning's *"the application processor
never lets the crystal go"* headline is **withdrawn** — it described the
platform, not a pmOS defect. The halving's whole weight now rests on **residency**
(track R): how much of the night the phone is actually suspended, and what a
suspend costs. Step 0 is therefore no longer merely first — it is the only
remaining measurement that can price the goal.

### Step D1 (track D) — **the oracle's own A/B, which has never been run**

Every A/B on the duty gap has been run on pmOS. The oracle has only ever been
*snapshotted*. So the one-sided rule this project keeps writing down has been
broken on the lever itself: we do not know whether the oracle's 6.1 % survives
losing its data context.

- on slot_a: `modem-window.sh` with the ofono context **active**, then the same
  window with it **deactivated**, then active again.
- ☠️ record the radio context on every leg (`radio-context.sh`); the 08-24 oracle
  capture's whole caveat is that its radio state was never recorded.

**Pre-registered reading:**

| oracle without data | meaning | consequence |
|---|---|---|
| duty **rises toward ~35 %** | the data context *is* the difference — and our flat bearer A/B on pmOS was measuring a bearer that is not equivalent to theirs | reopen the bearer question, this time asking **what is different about their context** (QMAP/mux config, DRX, the netmgrd setup), not whether one exists |
| duty **stays ~6 %** | the context is irrelevant; the difference is in **attach-time configuration** — DRX/paging cycle, or what the vendor RIL negotiates at registration | → D2 |

☠️ Note which way this cuts: the second outcome retires the most attractive
remaining story (the `netmgrd`/`ipacm` one) and points at a harder problem. Record
that here so the reading afterwards is not free to prefer the first.

### ✅ D1 ANSWERED 2026-08-30 13:35–13:54 — the context is not the difference

`ut-context-ab.sh 360` on slot_a, three windows, one instrument
(`captures/2026-08-30_oracle-context-ab/`):

| leg | data contexts | **MPSS awake** | signal |
|---|---|---|---|
| A | two | **6.9 %** | 30 |
| B | one (`DeactivateAll`) | **5.2 %** | 20 |
| A′ | two, restored | **5.4 %** | 22 |

**The duty did not rise — it fell slightly**, and A′ sits closer to B than to A,
so the spread is baseline drift rather than the lever. The oracle runs at 5–7 %
with a bearer and without one; pmOS runs at 34.8 %.

⇒ **The second branch of the reading table.** The `netmgrd` / `ipacm` story is
**retired** — the outcome the table named as the one that retires it, written
down before the run. It also *confirms* the pmOS-side bearer A/B rather than
casting doubt on it: two independent systems, same lever, same flat answer.

⇒ The duty gap therefore points at **attach-time configuration** — DRX, paging
cycle, or what the vendor RIL negotiates at registration. That is step D2.

☠️ Two notes that weaken rather than help: `DeactivateAll` left the IMS context
up, so leg B was *one context instead of two*, not *no bearer*; and the signal
drifted 30 → 20 → 22, which costs a modem **more**, so the confound pushes
against the observed direction rather than producing it.

### Step D2 (track D, only if D1 says "attach configuration")

Name what the modem is *doing* at 34.8 %, rather than guessing another lever. The
DIAG path is the instrument that can say it (`diag-handshake.py`, `diag-probe.py`)
— RRC state, paging cycle, DRX. ☠️ Confirm on the oracle that the endpoint is the
right one before reverse-engineering its protocol; a content-independent echo
means a stub endpoint, not a wrong framing.

☠️☠️ **Three constraints that make D2 a project, not a measurement**, all read out
of the tools' own headers before planning anything around them:

1. **DIAG is an intervention, not an observation.** `struct diag_ctrl_msg_diagmode`
   carries a **`sleep_vote`**, so bringing DIAG up changes the peripheral's sleep
   behaviour. It can therefore never run *during* a duty or residency
   measurement — it would be measuring its own instrument.
2. **One attempt per boot.** The peripheral answers the feature mask exactly once;
   a second endpoint afterwards draws 9 bytes instead of 2225 and gets no reply.
   A retry inside one boot measures an already-consumed state machine, which
   looks identical to "the modem does not answer" — and probably *was* what
   several earlier attempts measured. Reboot between attempts.
3. **The data channel does not answer yet.** As of `leads/diag-bringup.md`, the
   control channel talks (2225 bytes, 30 packets, parsed) and the data channel
   does not; the AP half of the handshake has to be copied from the vendor
   driver, not guessed.

⇒ Treat D2 as **bring-up work with a reboot per attempt**, and schedule it only
when nothing else is in flight.

#### ★ The design that gets a control out of the one attempt — added 2026-08-30

Constraint 1 and constraint 2 together look like they forbid a control: DIAG
perturbs the sleep behaviour, and there is only one attempt per boot, so there is
no second boot in which to measure the unperturbed case *under the same
conditions*. Read again, though, the constraint is on **opening DIAG**, not on
the duty instrument, and the two can share a boot:

1. `modem-window.sh` — one duty window with DIAG **closed**;
2. open DIAG (`diag-handshake.py`, the one attempt this boot allows);
3. `modem-window.sh` again, DIAG **open**, then ask it the RRC / paging / DRX
   questions.

Pre-registered reading, so it cannot be chosen afterwards:

* **the two duty windows agree** ⇒ opening DIAG did not move the thing being
  explained, and the RRC/DRX numbers describe the regime we care about;
* **they differ** ⇒ every number DIAG reports describes a *perturbed* modem and
  must be written down that way. It does not make them worthless — it makes them
  a different measurement, of a modem with a DIAG session open.

☠️ Checked in the source rather than assumed: `diag-handshake.py` sends
`DIAGMODE` with `real_time=1` and **`sleep_vote` deliberately 0**, so the
intervention is smaller than the header's general warning implies. That is a
reason to run the control, not a reason to skip it — the vote is one mechanism by
which DIAG could perturb the modem, and a zero in a field we chose is not
evidence about the others.

Cost: two extra duty windows in a boot that has to happen anyway. Without it, any
D2 number is single-sided, which is the failure this project has already paid
for more than once.

### Step R1 (track R, responsiveness — carried over, demoted)

Only after step 0 has priced suspend. Three open threads, in order:

1. ☠️ **The suspend marker is still in the wrong place.** `systemctl suspend` is
   not the suspend — logind runs ModemManager's terse path and waits for its
   replies before the kernel freezes, so the handshake lands inside the window.
   Move the marker into `/usr/lib/systemd/system-sleep/`, which runs after every
   inhibitor, and re-run the census. **Until then, whether the modem sends
   anything unprompted while asleep is unanswered** — three boundary errors in one
   day, all of the same class.
2. **Does the phone ever ask for a suspend by itself?** `idle-suspend-window.sh`
   is written and unrun. Every sleep so far was an explicit `systemctl suspend`.
   ☠️ The measurement's own ssh connection forbids the thing it measures — start
   it and let go; the witness is the host USB log.
3. **The selective wake filter** (`leads/selective-smd-wakeup.md`): the wake list
   is Voice (39) + WMS (51), **both measured**, and the noise is NAS (40) / DSD
   (52). Design only; it must not be built before 1 answers whether there is
   anything to filter.

#### ★ R1b's question got bigger 2026-08-30 — read this before running it

Prompted by an outside claim that pmOS drains double because "suspend is
broken". Checked, and the claim is half right in a way that moves the work:
see `bringup/leads/opportunistic-sleep-missing.md`.

* **Suspend is not broken here** — ten consecutive step-0 rounds each slept the
  full 602 s and every one ended on the RTC alarm. With ModemManager running,
  `sleep-night.sh`'s own header records every suspend dying within 16–53 s. It is
  *interrupted*, not broken.
* **Half the autosleep mechanism is not compiled in.** The wiki names
  `CONFIG_PM_WAKELOCKS=y` **and** `CONFIG_PM_AUTOSLEEP=y`; `config-fp3.aarch64`
  has the first and `# CONFIG_PM_AUTOSLEEP is not set`, so `/sys/power/autosleep`
  does not exist. The userspace half (`stated`) is not packaged for pmOS either.
* ☠️☠️ **A claim that lived twenty minutes.** From pmaports it looked as though
  only the AC branch was overridden, leaving `sleep-inactive-battery-type` at
  GNOME's `'suspend'` — so the phone would suspend on battery and never on the
  cable, and we had only ever measured the cable. **Measured on the device the
  same afternoon: both branches read `'nothing'`.** The override file consulted
  was the *GNOME Shell* package's and this device runs **phosh**. There is no
  unexercised branch; the phone suspends on idle on neither supply.
  The general trap: **a distribution's package source tells you what one UI
  package overrides, not what the running system has.** It cost twenty minutes
  rather than a night only because the claim was written down as a reading of
  package sources rather than as a measurement.

So R1b now carries three readings, not one: the `success` delta (does it suspend
at all), the on-device `gsettings` values for both branches, and what UPower
reports the phone is running on while the PMIC input is suspended. ☠️ **Do not
turn on `CONFIG_PM_AUTOSLEEP` off the back of this** — the wiki's own caveat is
that a wakelock must be held while the display is on, so autosleep without a
daemon is a phone that suspends while in use. And ☠️ none of this touches the
**awake** duty gap (34.8 % vs 6.1 %), which is where the arithmetic says the
halving actually lives; this lead must not be allowed to absorb track D.

---

## 4. Standing gates for the whole run

- ☠️ **No reboot with the PMIC USB input suspended**; no modem remoteproc restart.
- ☠️ **Do not poll the phone during a sleep measurement** — every ssh is a wake.
- ☠️ **Charging invalidates every current column.** Gate on it, or measure duty.
- ☠️ **A regime is not a bias.** Sleep length here ranges 61–601 s with the
  configuration unchanged. Any A/B on residency must gate its first leg on the
  regime and abort rather than compare across it.
- ☠️ **Before building on "nothing happened", find the line a success would
  print.** If there is none, silence is not evidence — probe the code path.
- ☠️ **A capture is true as of its date; the retraction lives elsewhere.** Read
  `findings-log.md` before quoting a capture's conclusion.
- Every claim states what it was compared against, and prints the command.
