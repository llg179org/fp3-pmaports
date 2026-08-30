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
| **D — modem duty** (34.8 % → 6.1 %) | 98.5 → **63 mA** | parity. **Cannot reach ≤50 mA, however complete** |
| **R — suspend** (the phone actually asleep, for real spans) | the only thing under the intercept | **this is where the halving lives** |

So: **track D is necessary and insufficient; track R is where the goal is won.**
Any run that spends a day entirely inside one of them has, at best, done half the
job — and both halves have been mistaken for the whole at least once.

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

Nothing else can be prioritised until this number exists. The goal's ≤50 mA row is
a *suspend* row, and it has never been measured on a system that could stay
asleep. It can be now: four consecutive 600 s windows were filled today.

- instrument: `bringup/tools/sleep-night.sh` + `sleep-night-fit.py`, control window
  in the awake regime (the instrument's own known-positive).
- ☠️ gate: the pack must be **off the cable** — a charging leg makes `cur_mA` the
  charge current and its p10 read 0.0. That has already spoiled one capture.

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

### Step X1 (track R, the real front) — **why does the RPM never reach vlow/vmin?**

The 633-line lead `bringup/leads/rpm-sleep-set.md` already frames it and the
instruments already exist: `rail-census.sh` + `rail-census-parse.py` name the
rails that vote active and never vote sleep; `sleepset-witness.sh` reads the
probe-time votes; `vlow-probe.sh` and `leg3.sh` test whether zeroing the sleep-set
XO vote changes anything.

**Pre-registered:** the output is a **named list of rails/masters that never vote
sleep**, and for each one the driver that votes it. A list is the deliverable; a
lever is what comes after. ☠️ If the census comes back empty, that is a result
about the instrument, not about the phone — validate it against a known positive
(a rail that *is* known to sleep) before believing it.

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

### Step D2 (track D, only if D1 says "attach configuration")

Name what the modem is *doing* at 34.8 %, rather than guessing another lever. The
DIAG path is the instrument that can say it (`diag-handshake.py`, `diag-probe.py`)
— RRC state, paging cycle, DRX. ☠️ Confirm on the oracle that the endpoint is the
right one before reverse-engineering its protocol; a content-independent echo
means a stub endpoint, not a wrong framing.

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
