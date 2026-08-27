# Status — where the port stands right now

> ⚠️ **AI-generated.** This page was written by Claude working under the
> direction of Lajosházi, László Gergely, who reviewed every change and made or
> reviewed every measurement it rests on.

**This file is the live one.** It is rewritten as work happens, not at the end of
a session, and it is the first thing to read when picking the work back up. The
reasoning behind each open item is in [`TODO.md`](TODO.md) — the by-item view, with the
by-branch view folded in at its end since 2026-08-24; closed items move verbatim
to [`TODO-DONE.md`](TODO-DONE.md). When this page and `TODO.md` disagree, **this one
is newer and `TODO.md` is more complete** — fix whichever is wrong rather than
picking a winner.

☠️ Every line below is the kind that goes stale first. Each row says how to read
it off the device instead of trusting it.

Last updated: **2026-08-27 (14:20) — the matched ladders landed, the gauge was
caught lying by 30 points, and front two has its first real hit: wlan is worth
~15 mA of median, confirmed at the rail. ~30 mA of burst still unexplained.**

**1. THE TWO EIGHT-HOUR LADDERS (the headline).** Eight matched one-hour rungs on
each system, back to back, panel provably off in all sixteen: oracle 14:07-22:10,
pmOS 23:10-07:13, the pack charged back to 94 % / 4.394 V **on the UT side**
before the slot switch. **Energy 525.6 mW (UT) vs 593.5 mW (pmOS) = +12.9 %.**
Floor 72.2 → **56.9 mA (ours is 21 % BELOW the oracle's)**, median 126.3 → 161.8
(+28 %). **We sit quieter and wake more expensively.** ☠️ Compare energy, not mA:
the ladders covered different parts of the pack and 6.6 of the 19.5 mA-points were
the discharge curve. ☠️ And +12.9 % is a LOWER BOUND — see 3.

**1b. THE SAME LADDERS AS CHARGE MOVED.** UT `cap` 94→69 = **25 pt**, voltage
4.262→3.967 = **295 mV**, coulomb 92.4→76.0 = **16.5 %**. pmOS `cap` 92→63 =
**29 pt**, voltage 4.150→3.708 = **442 mV**, no coulomb. **On the oracle's scale
the pmOS ladder moved 86.8 → 33.5 ≈ 53 pt — roughly TWICE the charge** while our
gauge claimed 29 against 25. The voltage travel says it unmapped: 442 vs 295 mV,
ending 259 mV below anywhere the oracle went. ☠️ The oracle-scale column maps pmOS
voltages through the UT ladder's V→`cap` points, anchored below by the 3.735 V OCV
→ 33.5 % cross-check; **below 3.967 V the oracle ladder has no data** and those
rows hang off that one anchor. ☠️ Its top row is contested by ~6 points (86.8 % by
voltage vs ~93 % by time budget — 7.2 pt would need 1202 mA for 11 min, where an
implausible 800 mA boot costs 4.8); a constant offset is excluded (the +90 mV that
fixes the start puts the end at 44 %). The conclusion survives either way (53 or
59.5 pt, both ≈2× the oracle's 25). ☠️ RETRACTED: my "boot + two probe rungs
explain the 94→87 gap" — the arithmetic kills it.

**1c. ★ PROTOCOL, mandatory for every comparison ladder from here on:** before the
slot switch, on the source system, **charge input OFF and pack rested**, record
`capacity` AND `voltage_now`; the first rung on the target system must open at that
voltage. That pins the two ladders' start points by construction instead of leaving
them untied across gauges 30 points apart. Charging inflates the reading (4.379 V
charging vs 4.262 V the moment the input was cut — 117 mV was the charger). If the
first rung does not open there, the gap is real consumption between the two
readings and gets logged, never absorbed.

**2. ☠️☠️ OUR FUEL GAUGE IS ~30 POINTS OPTIMISTIC, and this outranks the idle
work.** Same pack, minutes apart, across one slot switch: **pmOS 63 % / ocv
3.735 V against UT 33-34 %** (`cc_soc` 3389). The oracle's two numbers are NOT
independent (one QG block); the independent handle is the OCV, and 3.735 V after
300 s of rest is the 25-35 % region. ☠️ Then a **reboot moved our own reading
63 % → 51 %** on an unchanged pack — an integration fault's signature. **The
phone tells its owner it has twice the battery it has.** This voids the
`capacity` row of the ladder comparison and the runtime estimate from it (32.0 vs
27.6 h); it does NOT touch the energy figure. Decided only by one full
instrumented discharge to shutdown — which also yields the OCV→SoC curve this
pack has never had.

**3. ☠️☠️ THE ORACLE HAS A COULOMB COUNTER AND WE DO NOT.** Where both exist they
disagree **2.056×** over the same eight hours (integrated 1030.6 mAh vs coulomb
501.2 mAh) — the direction rules out sampling shortfall, since too few samples
under-count. Likeliest: **the sampling itself wakes the phone.** That ratio must
not be carried to pmOS to "correct" its numbers — it is a property of how often a
system wakes, the very quantity under test. Consequence: if our wake-rate is
higher, our distortion is LOWER, so the true gap is **between +12.9 % and
+132 %**. Narrowing it needs a mainline coulomb counter, now the
highest-value instrument work here.

**4. WITHDRAWN: the 15.3 mA oracle floor** and the "3.5× against us" framing THE
GOAL was scored on for two days. One window (08-24); the state-of-charge story
died on its own test — over 94 % → 69 % the oracle's floor does not move
(69.0-76.6 mA, no trend) and rung 5 covers exactly that capture's 4.050 V at
**71.0 mA**. Reproducible oracle figure: 69-77 mA floor / 59-64 mA integrated.

**5. THE AWAKE-BURST HUNT (front two) — first measured result.** systemd's PSI
watch costs **~26 mA of median and nothing on the floor.** A-B-A', 8-min windows,
panel proven off in all 97 samples of each:

| leg | PSI watch | `psimon` | fds | floor | median | mean |
|---|---|---|---|---|---|---|
| A | on | 3 | 11 | 57.5 | 160.2 | 158.6 |
| **B** | **off** | **1** | **6** | 57.8 | **130.2** | 144.1 |
| A' | on | 3 | 11 | 57.2 | 152.9 | 146.2 |

☠️ **The mean and median disagree and that is the finding**: the median drops
26.4 mA against the baselines' 156.6 (3.6× their own 7.3 mA spread) while the
mean drops 8.3 mA, inside baseline variation. It suppresses the *typical* sample,
not the big bursts. ☠️ **Two baselines is not a variance estimate** (n=2) — repeat
before attaching a number to it or making it a default.

☠️ **The knob is NOT `systemd-oomd`** — stopping it does nothing (`.socket`
restarts it, and even `inactive` left all 3 `psimon` + 11 fds). **systemd itself**
holds them: pid 1 and the user manager for `init.scope`, plus one
`memory.pressure` each for journald/logind/nsresourced/timesyncd/udevd. The knob
is `DefaultMemoryPressureWatch=no` in
`/etc/systemd/system.conf.d/50-fp3-no-psi-watch.conf`, it needs a **reboot**
(`daemon-reexec` leaves started units watching), and it is **partial**: 3 → 1
`psimon`, 11 → 6 fds; the residue is systemd's own `init.scope` watches. **The
file is currently REMOVED — the phone is back on stock behaviour (A' state).**

**5b. ★★★ AND THE BURST IS NOT CODE AND NOT THE CPU.** Two instruments sharing no
mechanism, both on a dark panel with the charge input cut:

* **the trace** (`burst-source.sh`, 24 321 workqueue+timer events against 71
  current samples): splitting every event into the 5 s bin ending at each current
  sample, **burst bins 313 events, quiet bins 316** — every top function at the
  same per-bin rate, the 1 % difference pointing the wrong way.
* **the sysfs sampler** (`burst-attrib.sh`, no tracepoints, 180 samples, current
  53 → 473 mA = **9×**): `busy_pct` **1 vs 1**, power-collapse residency **99 vs
  100 %**, wakes 77/s vs 77/s, both cpufreq policies pinned identically, wlan 2
  pps vs 2 pps. **The cores are collapsed 99 % of the time during the burst.**

☠️ The trap avoided: `psi_avgs_work` is 4 897 of ~9 000 workqueue executions and
looks exactly like an answer — until the split shows it flat end to end. **Rank a
trace and you describe the background; split it by the thing you are explaining
and you test it.** (It is still a real ~26 mA of median as item 5 says — a steady
tax, not the burst.)

**5c. ★★★★ WLAN IS THE FIRST REAL HIT — ~15 mA of median, and the rails agree.**
A-B-A' with `nmcli radio wifi off`, panel dark in all three legs:

| leg | wlan | floor | median | p90 |
|---|---|---|---|---|
| A | on | 53 | 99 | 221 |
| **B** | **off** | 53 | **83** | **198** |
| A' | on | 53 | 98 | 217 |

Median: **1.0 mA of baseline spread against a 15.5 mA effect.** p90: 4.0 against
21.0. ☠️ The mean (4.9 vs 6.5) and the energy (23.8 vs 27.4 mW) do NOT clear their
spread — the median and p90 are the measurement, "wlan costs 27 mW" is not. Floor
untouched. B is n=1.

☠️ **The obvious fix was dead before it was built.** `wcn36xx` with `debug_mask` =
`WCN36XX_DBG_PMC` prints `Entered BMPS`: power save works. What it shows instead
is **churn — 8 entries in 180 s, in clusters**, each implying an exit, and between
exit and re-entry the radio is in full receive. Background broadcast at 1–3 pps is
enough. Some of it may be ours: the dev host is on the phone's wlan subnet.

**The rail census says the same thing at the rail.** 57 regulators, `state` AND
`opmode`, 186 samples: **72 of 81 readings constant, 9 move.** Three are
identifiable and are exactly the right three — `l9` = `iris-vddpa` (515 mA
requested max), `l19` = `iris-vddrfa`, `l7` = `iris-vddxo`, i.e. the WCN36xx RF
and PA rails. ☠️ The other four movers (`l1`, `l4`, `s1`, `l18`, 43 % vs 20-23 %)
have no consumer anywhere in `regulator_summary` and are not being guessed at.

☠️☠️ **The first version of that census was retracted** — labels off by the gaps
(bare vector against a header name list, three regulators with no readable
`state`), and the instrument loaded what it measured (114 forks/sample, 156
samples where 180 were due). Now every reading carries its own key and it is two
`grep -H .` per sample; the re-run returned 186.

**5d. WHAT IS STILL UNEXPLAINED: ~30 mA of burst.** With the radio entirely off,
leg B still ran median **83 against a floor of 53**, 97 of 181 samples still
bursts — with the modem excluded, the cores collapsed and the panel dark. The
census is being repeated with both radios down.

Also live and unexplained: a real **~81 s period on pmOS that the oracle does not
have** (harmonic at 162 s; oracle ±0.03), strong in ladder rungs 1-4, weak after.
A 6-minute traced window found no function with that period — too short. ☠️ The
current↔trace correlation is a dead end: instantaneous samples cannot be
correlated against continuous event counts, and best-of-13-shifts inflates r.

**5e. ★★★★ 2026-08-27 EVENING — THE BURST HAS AN OWNER: THE MPSS CORE.** The
"~30 mA still unexplained" above is now attributed, and the ~15 mA of it that was
never the wlan is the same actor. `burst-master.sh` samples the RPM's per-master
record — shutdown count, XO shutdown count, XO-off duration, active-core bitmask —
alongside the current. Its **burst/quiet split answered "not me" for the sixth
time, and the answer was in the same file**: a master that is up a third of the
time has a median of zero on *both* sides of a split by current. Split by the
candidate **cause** instead, over two independent windows:

| | window 1 | window 2 |
|---|---|---|
| MPSS core up | 62/189 = **33 %** | 69/189 = **37 %** |
| median with MPSS up | 166 mA | 158 mA |
| median with MPSS down | 74 mA | 67 mA |
| **difference** | **+92 mA** | **+91 mA** |

The two sides each drift 7–8 mA between windows and the difference moves by 1 mA.
The 2×2 with PRONTO is close to additive — both down **63 mA**, PRONTO alone
108 mA, MPSS alone 163 mA, both 188 mA — and the two are not the same variable
(they agree on 107 of 189 samples). At 35 % duty, MPSS carries ~32 mA of the
median: the size of the residual.

This reconciles the flat modem A-B-A′: `mmcli --disable` stops the **RF**, not the
**MSS core**. And it puts one suspect on both fronts at once, since the same
subsystem's SMD edge terminates every suspend (IRQ 141).

☠️ Correlation over two windows, not an intervention; the duty cycle is
point-sampled at 2 s; and the instrument does **not** resolve the ~15 mA wlan
effect known to be present, so its *nulls* rule nothing out at that scale — only
its separations count. The intervention (A-B-A′ on `mmcli --disable`, comparing
**MPSS duty**, not current) is running.

**5f. And one for the floor, not the burst: LPASS never releases the crystal.**
`LPASS_xopct` is 0 in all 189 samples of both windows, and its `XO total duration`
is **9.4 s against 5½ hours of uptime**. Constant, so it cannot be the burst — but
a master that never lets the XO go is exactly the shape of the standing `vlow = 0`
item. First suspect is a userspace sensor consumer holding the ADSP up.

**5g. ★★★★★ 2026-08-27 — THE ORACLE COMPARISON, AND IT NEEDED NO SLOT SWITCH.**
Both Linux-side levers on the MPSS finding came back flat — `mmcli --disable`
(36/34/34 %) and stopping `ModemManager` (38/36/37 %), with the modem's own SMD
edge reading **zero** through the leg with the daemon stopped. So the MSS core
wakes on a schedule Linux neither sets nor sees. The question became whether the
oracle pays it too, and the answer was already committed: a 565 s **UT awake-idle
window from 2026-08-24** (slot a, cable in, screen off), taken for the `vlow` work.

| master | oracle awake | pmOS awake (3 windows) |
|---|---|---|
| APSS | 100 % | 100 % |
| PRONTO | 23.2 % | 24.7–26.7 % |
| **MPSS** | **6.3 %** | **34.0–36.4 %** |
| **LPASS** | **2.9 %** | **100.0 %** |

☠️☠️ **AND THE TWO SYSTEMS DO NOT RUN THE SAME MODEM FIRMWARE.** Read off the
device: both modem partitions carry MPSS build **325768** (the 2021-10-25
`SDM632.LA.2.1-00015` metabuild that also supplies the RPM, TZ and bootloader on
either slot), while pmOS loads its own rootfs copy, build **425464**. So the 6.3 %
and the 34–36 % were measured on different modem images, and that sentence belongs
next to those numbers wherever they appear. It is also the only difference left
after every Linux-side lever came back flat — the swap procedure and its rollback
are in `TODO.md`, not run, because it rewrites firmware and needs a reboot.

PRONTO matching is the control that makes the rest readable. **MPSS is awake 5–6×
more on pmOS at the same XO shutdown rate** — each awake stretch is longer, not
more frequent — which at the measured +91 mA is ~25 mA of median. ☠️ And **LPASS
never sleeps here at all**: 9.4 s of XO-off in 5½ hours against the oracle's 97 %.
Constant, which is why no burst instrument ever saw it; they were all built to
find things that change.

☠️☠️ **The LPASS half is a re-opening, not a discovery, and it is worth less than
it looks.** `power/bringup/leads/lpass-never-sleeps.md` was **closed on
2026-08-22** with the sentence "the LPASS now duty-cycles and re-enters XO
shutdown within ~30 s of audio use" — false on the device today, five windows out
of five. But the same page already **priced** it: with the DSP stopped outright
the current moved ~4 %, inside the instrument's spread. So this is a correctness
item and an explanation for `vlow` = 0, **not** a lever on the floor, and the
measurement queue must not be re-ordered around it.

☠️ The plan of record was to spend a slot switch re-taking this. **Before
measuring, grep the captures** — they are indexed by date and question, not by
what they contain.

**6. Instruments written today**, all in `power/bringup/tools/`:
`night-ladder.sh` (+ its two units, reboot-surviving, charge-input-safe),
`ladder-summary.py` (integrates I·V, not just I), `burst-profile.py`,
`burst-source.sh` (wraps idle-ab rather than duplicating its panel logic — the
first version duplicated it and aborted where idle-ab succeeded in the same
minute), `burst-attrib.sh` + `burst-attrib-fit.py` (the machine measured about
itself, no tracepoints; the fit splits by burst/quiet and names which of three
verdicts the data supports), `burst-modem-ab.sh` (A-B-A' on the RF),
`discharge-run.sh` (**the one instrument here with no capacity floor** — it
measures the pack, and `capacity` is what is under test; refuses to start below
97 % or with the panel up). ☠️ `idle-ab.sh` records `wifi: ?` on pmOS: the most obvious periodic-task
suspect is the one field the instrument leaves blank. Worth closing before
hunting further.

Standing from 2026-08-25: the two biggest wakers found so far were both OURS
(`apcs_hold_cluster()`'s global `cpu_latency_qos`, fixed in r76; and a `spkwatch`
harness left running since August) — median 148-157 → 98.3 mA. The census against
the oracle excluded the modem (30.8/31.1/31.1/31.1 mA over four legs), the debug
UART, and the `s3`/`s4` rails (☠️ `regulator_summary` is a **tree** — indented
rows are child regulators; leaf for leaf the rail sets match). ☠️ 74 ssh logins in
70 minutes cost 18.3 mA: do not poll during a leg. ☠️ `boot-deploy` rewrites
extlinux.conf on every kernel install. ☠️ `pkill -f` matches its own command line
— it bit again today.**

## The device

| what | value | how to check |
|---|---|---|
| kernel package | **`linux-fp3-7.1.3-r77`** — config-only build on the same `_commit`, adding `CONFIG_PM_DEBUG=y`/`CONFIG_PM_SLEEP_DEBUG=y`. ☠️ Deployed **by hand**, not via `apk add`: the files were copied into `/boot` under versioned names and `extlinux.conf` rewritten, so `boot-deploy` never ran and the fallback net was never destroyed. `apk info` therefore still reports r76 — the package database was deliberately not touched | `uname -v` (`#78-fp3`), `sha256sum /boot/vmlinuz-r77` |
| build stamp | **`#78-fp3`** | `uname -v` |
| pinned commit | `debug-int/7.1.3` `5aafd59e` | `grep _commit linux-fp3/APKBUILD` |
| boot config | **3 labels**, rebuilt 2026-08-26 for r77: default `postmarketOS` → `/vmlinuz-r77`; `postmarketOS-r76`; `postmarketOS-r73`. All three carry `panic=10`, all six files verified present, and the three kernels are **distinct images** — `02-boot-fallback` passes on all four sub-checks. Previous file kept as `extlinux.conf.pre-r77`. The r76 description below is history: **3 labels**, all with `panic=10`: default `postmarketOS` → **frozen** `/vmlinuz-r76` + `/sdm632-fairphone-fp3.dtb-r76`; `postmarketOS-r73` fallback; `postmarketOS-headless` (same r76 snapshot + `systemd.unit=multi-user.target`, for GUI-less legs). ☠️ The default was pointing at the LIVE `/vmlinuz` symlink until 2026-08-25 evening, which is the r74 no-boot trap — the next package install replaces the kernel under the label that boots by default, on a phone with no console. `preflight.sh` refuses to arm a night on that, correctly; the snapshot was verified by sha256 against the running kernel before the config was switched. ☠️ `boot-deploy` rewrites this file on every kernel install and drops all of it — restore by hand afterwards | `cat /boot/extlinux/extlinux.conf` |
| last full battery | **29 ok / 2 failed / 3 skipped** (2026-08-23 17:11, r73). ☠️ Read that number with care: the failures were `98-camera-af-rail` and `99-suspend`, and neither is a check defect — **the camera wedged and the watchdog reset the phone mid-run** (queue item 4). ☠️ It also predates the runner fixes of 2026-08-23, so its `ok` count includes checks scored green after the reset | `tests/fp3-selftest` |
| last camera-block run | **8 ok / 0 failed** on a fresh boot (2026-08-23 late, r73), and the same block wedged the phone earlier the same evening — the fault is intermittent, ~1 run in 2 | `tests/fp3-selftest --only camera,suspend` |

☠️ Two successive prose copies of the boot config stood here and **both** went
stale — the second one, "5 labels, default `postmarketOS-prev`", contradicted the
table directly above it while claiming to correct it. The table row is the
current one (3 labels, default `postmarketOS` on the frozen r76 snapshot). Read
`/boot/extlinux/extlinux.conf` off the device rather than trusting any prose copy
of it, this sentence included.

## Branch tips

☠️ Read these off the fork, not off this table — `git ls-remote fork
'refs/heads/*7.1.3*'` answers the whole thing in one command, and a local
checkout can be behind (it was, below). Measured 2026-08-25 evening:

| branch | tip on `fork` | note |
|---|---|---|
| `7.1.3/main` | `72138559` | the upstream `msm8953-mainline` release we sit on |
| `wip/7.1.3/audio` | `42b7e745` | + the three SSR fixes of 2026-08-23 |
| `wip/7.1.3/camera` | `a253e401` | ☠️ **one commit ahead of `integration`/`debug-int`**: `media: i2c: ak7375: do not power the motor up on a system resume`. The category rule is *unfinished* on it — steps 2 and 3 (cherry-pick to `integration/7.1.3`, carry to `debug-int/7.1.3`) are not done, deliberately: the autofocus regression has not been run. Do not ship until it is |
| `wip/7.1.3/charger` | `f5da2bfd` | |
| `wip/7.1.3/power` | `68dcadbd` | the cluster-local cpuidle PLL-relock hold (shipped as r76) |
| `wip/7.1.3/sensor` | `cc39f522` | |
| `wip/7.1.3/voice` | `bf453330` | |
| `integration/7.1.3` | `9ebb552a` | |
| `debug-int/7.1.3` | `5aafd59e` | **this is what the package pins and what the phone runs** — `pkgver=7.1.3`, `pkgrel=76`, `uname -v` → `#77-fp3` |

`submit/7.1.3/*` exists for `audio` `f71226ac`, `camera` `7ea4a589`, `charger`
`a800c7ec`, `i2c` `5560f875`, `power` `ca27e77f`, `sensor` `478fa63d`, `voice`
`faac4c7d`.

☠️ **The three paragraphs that stood here said the device runs r73 (`8d7ecf9`)
and that the package still pins it.** Both were true on 2026-08-24 and false by
the next morning: the PLL-relock redesign shipped as r76 (`5aafd59e`) and the
phone has been on it since. This is the exact failure mode this file warns about
in its own header — a status line that was accurate when written. Check
`apk info -vv | grep ^linux-fp3` and `uname -v` before believing any revision
number on this page.

★★ 2026-08-24 (superseded by r76, kept for the mechanism): the all-20-rails
`regulator-state-mem` commit (r74,
`84241a07`) **did not boot** and is now **reverted** on all three branches
(`wip/power` `53e51066`, `integration` `140ff98e`, `debug-int` `8d7ecf9`), pushed
to `fork`. `linux-fp3` re-pinned to `pkgrel=75`,
`_commit=8d7ecf9153cde4c1a80f0f1d4f53562524a30598` (reverted debug-int, content
≡ the running r73 kernel). Why revert: a one-rail bisection probe proved the
mechanism is sound (state-mem on only `pm8953_s3` boots, casts the vote —
`sleep smpa/3 swen=1 @ t=0.276084` — and suspends), so the all-20 no-boot is the
`regulator_register()` all-or-nothing behaviour tripping on one specific rail;
**and** `on-in-suspend` saves no power anyway (rail stays on, only the vote
exists). `vlow` is unchanged (still 0) — the deep-sleep win is gated behind the
AP-XO regression, not the LDO votes. Full detail:
[`power/bringup/findings-log.md`](power/bringup/findings-log.md) 2026-08-24
one-rail entry.

`fp3-pmaports` `origin/main` carries the docs and the APKBUILD; the kernel goes
to remote `fork` only, over port 443, and never to `origin`.

## ☠️ Resume here after a compact or a long gap

## ✅ RESOLVED — r74 no-boot cause found + reverted (2026-08-24); device since moved to r76

The device is up and answers on SSH. ☠️ The heading and the paragraph here said
**"device on r73"** until 2026-08-25 evening; it has run **r76** (`5aafd59e`,
`#77-fp3`) since the morning of 2026-08-25. r74 stays on `/boot` untouched for
diagnosis; the boot default was moved off it and is now a frozen r76 snapshot.
Kept below because only the boot was recovered — the r74 *cause* is not fixed.

**r74 does not boot.** Deployed, rebooted 22:45:10, never re-enumerated on USB or
WiFi. The host log shows the `cdc_ncm` disconnect and **no re-enumeration** — and
that absence is the informative part: `panic=10` is on every entry and the debug
layer starts the watchdog at probe, so a *later* hang would produce a reboot
**cycle**. There was none, so the kernel stops **before the watchdog probes**.

**Prime suspect: the change itself, `regulator-state-mem` on all 20 rails.**
Read out of the source after the failure:

- `suspend_set_initial_state()` runs inside `regulator_register()`
  (`core.c:1497`), one of the earliest things on this SoC for the RPM rails; the
  change makes it send 20 extra `qcom_rpm_smd_write()` calls into the RPM
  **sleep** set right there.
- `qcom_rpm_smd_write()` (`soc/qcom/smd-rpm.c:139`) waits on the ack with
  `RPM_REQUEST_TIMEOUT = 5 * HZ`, returning `-ETIMEDOUT` or the RPM `ack_status`.
- ☠️ **`regulator_register()` treats that as fatal** (`if (ret < 0) return ret`),
  and `rpm_reg_probe()` returns out of its child loop — so **one rejected or
  timed-out sleep vote unregisters every rail on the board**. No regulators →
  no storage, USB or display: the silent early stop observed. 20 rails × 5 s is
  also up to 100 s of blocked probe.
- ☠️ A NULL `smd_vreg_rpm` was checked and **ruled out** (assigned before the
  loop, `qcom_smd-regulator.c:1530`).

**Hypothesis, not measurement.** The next attempt must not be "all 20 rails
again with a tweak": start from **one** rail and read the boot before the second.

**How it was recovered (the route that worked):** stock ABL fastboot →
`set_active a` → UT boots (adb as `phablet`, sudo `<pw>`) → mount pmOS's
embedded `/boot` off `system_b` (`losetup -o 1048576 <loop> /dev/mmcblk0p31`;
mount RW) → edit `extlinux.conf` default to `postmarketOS-prev` (r73) → sync,
umount, `losetup -d` → `sudo reboot bootloader` → `set_active b` → `reboot`.
pmOS came up on r73 in ~15 s; `02-boot-fallback` passes and the running tree has
**zero** `regulator-state-mem` nodes (proof it is r73). Full step-by-step in
`docs/TODO.md` (the ✅ RECOVERED block).

☠️ **Button-mapping correction, measured by the user.** **Volume-UP + power
reaches EDL** (`05c6:900e`); **volume-DOWN + power starts fastboot**. The lk2nd
menu is **not usable blind** — the screen stays black — so recovery goes through
fastboot + the UT-slot route above, never by picking an on-screen menu entry.
The earlier note (down→EDL, up→lk2nd menu) was inverted and is retracted.

☠️ **The guardrail was followed in letter and missed in substance, and that is
the lesson to keep.** "Put anything risky on the non-default label" was obeyed
by putting the *tracing arguments* on a separate label — but the tracing
arguments were never the risky part. The **device tree** was, and it is on
`/boot/sdm632-fairphone-fp3.dtb`, which **both** r74 labels point at. Isolating
a change means isolating the file that changed, not the flag that came with it.
A `-sleepset` label whose only difference is `trace_event=` is not an isolated
arm; it is the same arm twice.

☠️ Second thing this cost: `apk add` ran `boot-deploy`, which **rewrote
`extlinux.conf` from scratch** — dropping the fallback label, `panic=10` and the
menu timeout, exactly as `docs/deploy/README.md` warns. The rewrite afterwards
put all four labels back and `02-boot-fallback` confirmed them (4 of 4 entries
carry `panic=`), so the net that now has to be used was verified *after* the
install and before the reboot. The pre-install file is saved on the device as
`/boot/extlinux/extlinux.conf.pre-r74`.

**Where the change lives, so nothing is lost while the phone is down:**
`wip/7.1.3/power` `e59893af`, `integration/7.1.3` `4cf51780`,
`debug-int/7.1.3` `84241a07`, all pushed to `fork`. Package
`linux-fp3-7.1.3-r74` is built at
`/mnt/1TB/pmos/work/packages/edge/aarch64/linux-fp3-7.1.3-r74.apk`.
☠️ **Do not roll `_commit` back in the APKBUILD before the cause is known** —
the commit is not proven wrong yet, only the boot is proven broken.


The state that is *not* in git, in one place. Everything else is recoverable
from the repos.

1. ★ **There IS a half-finished step as of 2026-08-23 22:20: r74 is built or
   building, and is NOT deployed.** The RPM sleep-set DT commit is on
   `wip/7.1.3/power` `e59893af`, `integration/7.1.3` `4cf51780` and
   `debug-int/7.1.3` `84241a07`, all pushed to `fork`, tarball checked
   (200 real / 404 bogus). `linux-fp3` is at `pkgrel=74` with that `_commit`,
   checksummed, and the build log is `/mnt/1TB/pmos/build-r74-sleepset.log`.
   The remaining steps, in order:

   1. `apk add` the built package. ☠️ `--simulate` first and **read the output
      for `Purging`** — apk-tools 3 re-resolves the whole `world` on a single
      local install and has broken this device that way before.
   2. Re-arm extlinux and check the md5 of the deployed kernel/dtb. The net was
      verified intact just before the bump (`02-boot-fallback`: fallback entry
      present, menu armed, all three entries carry `panic=`, watchdog active).
   3. Add a **non-default** label carrying
      `trace_event=qcom_smd_rpm:qcom_rpm_smd_write trace_buf_size=8M`
      (the `postmarketOS-xo` label is the precedent for an experiment label),
      flip `default` to it, reboot, and run
      `docs/power/bringup/tools/sleepset-witness.sh` **early** — the ring
      overwrites the boot window within minutes. Then flip `default` back.
      ☠️ **Never add `tp_printk`.** The cmdline carries
      `console=ttyMSM0,115200`; a boot's worth of tracepoints at 115200 baud
      runs past the 20 s watchdog and boot-loops the phone.
   4. Only once the votes are witnessed does reading `vlow` mean anything.

   `wip/7.1.3/audio` is unchanged at `42b7e745`; nothing there is stranded.
2. The reproduction is `docs/audio/ssr-repro.sh` in this repo: one ADSP restart
   addressed **by name**, health measured before and at +20 s / +90 s, then a
   verdict table of named symptoms. Copy it to the device and run it under
   `systemd-run --collect` so the ssh session cannot contaminate it.
   ☠️ **An earlier version of it filtered `dmesg` by timestamp with awk and
   printed nothing at all** while `dmesg` held 225 codec lines including a
   `WARNING`. That silence read as a pass. The script now counts named patterns
   over the whole buffer and prints sanity rows that must be **non-zero**; if
   those are zero the instrument is blind, not the kernel clean.

3. **The test runner changed today, in three ways that affect how any past
   result should be read.** `tests/fp3-selftest` now (a) scores a check with no
   `PASS:`/`FAIL:` line as **FAIL — no verdict** instead of `ok`, (b) compares
   `/proc/sys/kernel/random/boot_id` across the run and **fails** the run if the
   phone rebooted under it, and (c) **fails** rather than passes when the device
   is unreachable at the end and the reboot cannot be confirmed. ☠️ Before (a),
   a battery that reset mid-run printed `ok:` for nine checks on a dead phone —
   so **any "N ok" from a run older than 2026-08-23 that reset is not
   trustworthy**. All three were shown firing and shown not firing before being
   believed.
4. **A hunt may be running on the device.**
   `docs/power/bringup/tools/camera-wedge-hunt.sh` reboots the phone once per
   pass, so a device found rebooting is expected rather than alarming. It writes
   `summary.txt`, `pass-N.log` and a `kmsg.log` spanning all passes into its
   output directory; kill it by the PID from `ps -eo pid,args`, ☠️ **never with
   `pkill -f`**, whose pattern matches the killer's own command line.

☠️ **Before starting anything power-related, read the modem-lead plan in
[`TODO.md`](TODO.md) ("Deep sleep — CLOSED" section) and the queue item above.** A finished
investigation that lives only in a `leads/*` working note is invisible from this
page, and on 2026-08-23 that produced a re-run of a closed bisect and a
conclusion that had to be retracted. If you close something, move the result to
the runbook in the same commit.

## ★ The primary goal, stated 2026-08-24 evening

**Bring pmOS's consumption down to the Ubuntu Touch level, or below.** Set by
Lajosházi, László Gergely; it replaces "reach a deep-sleep mode" as the thing
this track is for, and it is what "done" now means.

Why the restatement matters: the oracle does not get its number by sleeping.
Measured the same evening on the same protocol (panel **off**, radio up, WiFi
associated, on battery, via the newly validated `bms/cc_soc` coulomb counter),
**UT idles at 32.2 mA** where pmOS idles at 54 mA on its floor but **148 mA on the median** — measured 2026-08-25 by one instrument on both sides — and our best *asleep*
figure, the radio-low leg of the same day, is 40.8 mA. The oracle sitting awake
beats our phone asleep. So the gap to close is **idle depth**, not suspend, and
the target is a level rather than a mode.

**The matched pair (2026-08-25, `tools/idle-ab.sh` on both, panel proven dark,
compositor running on both):**

| | floor (p10) | median | integrated | voltage slope |
|---|---|---|---|---|
| UT | 15.3 mA | 30.1 mA | **32.2 mA** | 43.0 mV/h |
| pmOS r73 | 54.3 mA | **148.0 mA** | — | 133.7 mV/h |

**The shape is the finding.** pmOS's floor is close to its long-documented
58-63 mA, but its median is three times its own floor where UT's is barely
twice. So the gap is not a load that burns continuously — it is **wakeups**.
First evidence: with the panel dark, `IPI1` 1927/s and `arch_timer` 1037/s at
82-100 % CPU idle. ☠️ **A third figure stood in that sentence — `msm_mdss`
79/s "with the display off" — and it is WITHDRAWN**: that sample was taken with
the display *on*. With the CRTC proven off the display subsystem raises no
interrupts at all. The IPI and timer rates stand; the mdss one was an artifact
of the instrument, not of the phone.

**Where it went (2026-08-25, r76).** The wakeup half of this was chased down and
the two biggest wakers turned out to be **ours** — the global `cpu_latency_qos`
in our own PLL-relock guard, and a diagnostic harness (`spkwatch`) left running
since August. After: median **148-157 → 98.3 mA (−35 %)**, floor **54 → 52.9**,
burstiness **2.75× → 1.86×** against the oracle's 1.97×. So pmOS now bursts
*less* than UT, the wakeup half is substantially done, and **what is left is the
floor** — where seven separate exclusions have since produced no candidate at
all. See TODO "Where the hunt actually stands".

☠️ Earlier readings of the oracle (22, then 29.7 mA) came from shorter windows
and a different script; 32.2 is the one taken by the same instrument as the pmOS
row, and only same-instrument rows belong in this table. ☠️☠️ **And as of
2026-08-25 afternoon the whole UT column is in doubt** — "panel proven dark" was
proven with the *backlight*, which on the oracle is not a witness: its panel sits
fully powered at brightness 37 with the LCDB bias rails at 5500 mV. The same
instrument read the oracle's floor at **31.1 mA** across four legs the next day,
against the 15.3 here. Do not quote this table's UT row until that factor of two
is settled; it is item 1 of "Next, in order" in TODO.

★ **Half of that doubt was removed on 2026-08-26, and it was a wrong file, not a
lit panel.** One write of `4` to `fb0/blank` on the oracle moves every witness at
once: `panel_power_on` 1 → 0, backlight 25 → 0, and `lcdb_ldo`/`lcdb_ncp`
`state` **`enabled` → `disabled`**. What does *not* move is those rails'
`microvolts`, which stays at 5500000 — because that file reports the rail's
**configured** voltage, not whether it is switched on. Reading it is very
probably where "the LCDB stays at 5500 mV through a blank" came from. So the
oracle *can* be measured with the panel genuinely off, and the actuator was
working the whole time. ☠️ This does **not** validate the 15.3 mA row: it removes
one reason to disbelieve it and says nothing about the 31.1 mA. The re-measure
that settles it is running; until it lands, the UT row stays unquotable.

## The work queue, in order

Everything here is machine-doable unless the row says otherwise. Work down the
list; do not stop at the end of an item to report.

**Re-ordered 2026-08-24 night: the deep-sleep/`vlow` item CLOSED; the modem
lead takes slot 1.** Items 2 and 3
are directly under it (evidence retention, and the WiFi lever the same
measurement has to account for); the camera wedge, which led this list yesterday,
is now item 4.

### ★★★★ 2026-08-26 — the modem lead has a mechanism, and it is not current

### ★★★★★ 2026-08-26 06:45 — SOLVED: the modem's SMD edge ends every suspend

`pm_wakeup_irq` — which exists only since r77 shipped `CONFIG_PM_DEBUG` — names
it, 4 suspends of 4, and the kernel prints it once per suspend:

```
PM: suspend-to-idle
Timekeeping suspended for 8.081 seconds
PM: Triggering wakeup from IRQ 141
```

**IRQ 141 = hwirq 57 = `GIC_SPI 25` = `remoteproc@4080000/smd-edge` — the
modem's.** The edge reads `disabled` in `power/wakeup`, and that is *why* it
aborts: an interrupt arriving during s2idle on a source that is not registered
for wakeup is treated as an unexpected wakeup and **terminates the suspend**.

**The modem sends the AP something over SMD while the phone is asleep, and the
kernel aborts.** Everything else falls out: modem cut → 0 aborts in 6; the abort
length is simply the interval to the next message; the MPSS crystal churn is
scenery; and "post-boot decay" and "battery vs cable" were that same interval
under different labels.

☠️☠️ **Why it took all night, and it is structural.** The waking line is the
**quietest** in the table — 334 counts in total against the RPM edge's 50 591,
exactly one per suspend, because ending the suspend is all it does. Hours were
spent ranking interrupt deltas by magnitude; **a ranking instrument is blind to
the rare event.** And the instrument that names it directly was read as an empty
file for two days when it did not exist at all — one Kconfig symbol.

**Next:** what is the modem sending, and must the AP wake for it? `qcom_smd` is
upstream and every SMD-era Qualcomm SoC has these edges, so the answer is
upstream-shaped. Trace the rpmsg channel and payload of the message arriving
immediately after `PM: suspend-to-idle`.

<details><summary>The four stories published and retracted before this one</summary>

### ☠️ 2026-08-26 06:02 — "the suspend abort is a DECAY" (retracted)

The night's most useful result, and the cheapest experiment on the whole power
track: **reboot, wait, suspend.** Measured with `tools/suspend-rate.sh` from a
one-shot unit 240 s after a normal boot, modem registered, cable in:

| uptime at suspend | slept, of 600 asked |
|---|---|
| 262 s | **50 s** |
| 462 s | **168 s** |
| 780 s | **356 s** |
| 1 637 s | **601 s** (full term) |
| 2 340 s → 6 764 s, eight rounds | **602 s every time** |

**Something drains over the first ~20–25 minutes of a boot and takes the
suspends with it.** Not a binary state, not the radio as such — a decay. A queue,
a retry backoff, a registration procedure or a timer that stops being rearmed.

**Three candidates are dead, each on measurement:** the wake-armed modem edge
(every edge reads `disabled`), time-since-boot as a *binary* (leg A aborted 4.3 h
in), and ★ **the MPSS crystal churn** — its shutdown count per second *asleep* is
**2.4–2.5 in both regimes**, so it tracks how long the AP was down and nothing
else. The 2026-08-24 reading bundled two independent facts; one was scenery.

☠️ **One observation the decay does not explain:** leg A, 4.3 h into its boot,
aborted at 50/89/32/59 s with no upward trend — and it is the only run of the
night taken **on battery**. The identical series on battery is running now, with
its prediction registered in the findings log beforehand and a `deadman` timer to
restore the charger regardless of outcome.

**The instrument that would end this is not built:** `pm_wakeup_irq` needs
`CONFIG_PM_DEBUG`, staged in `0cc13b7` and not yet compiled. It is now clearly
worth a build.

</details>

☠️☠️ **OVERCLAIMED AND CORRECTED WITHIN THE HOUR, 2026-08-26 04:13.** What is
below was written as a categorical law — *"with the radio up, the phone does not
stay asleep"* — on five aborted suspends from two instruments. A third
instrument, one hour later, same kernel, same cable state, **modem registered on
LTE, slept the full 601 s of 600 asked.** So the abort is real but
**conditional**, and the condition is not yet named. Do not quote the law.

What still stands: the abort happens, it is large when it happens (67 s of 600),
and it never once happened with the modem cut. What does not stand: that it
happens *whenever* the radio is up. Candidate variables, none tested — time since
boot (the aborting arms were 11 min in, the full-term one 27 min), time since the
modem registered, and whether the pack was on battery or the cable.

**With the radio up, the phone sometimes does not stay asleep.** Measured on r76
by two instruments the same night:

| instrument | modem up | modem cut |
|---|---|---|
| A-B-A leg, 4 × 600 s requested | slept **230 s of 2400 (9.6 %)** | 2407 s (100 %) |
| `wakeup-census.sh`, 600 s requested | slept **67 s** | 601 s |

So "the modem costs ~36 mA asleep" was never a co-processor drawing current
beside a sleeping AP — it is **an AP that is not allowed to stay asleep**. The
census also shows the MPSS chopping its crystal **179 times in 67 s** and keeping
it off 52 % of the window, which reproduces the 2026-08-24 XO-duty result from a
different direction.

☠️ **Not the armed modem edge** — every rpmsg edge read `disabled` (the arm knob
resets each boot). That hypothesis died before it cost a measurement.

☠️ **What this cost, and it was avoidable.** `systemctl stop rmtfs` powers the
modem down and `systemctl start` does not bring it back — **recorded in the
findings log on 2026-08-21, with the fix written out, and never put into a
tool**. Five days later it destroyed the A-B-A's control leg. Four tools had the
defect; `slope-leg.sh`, `wakeup-census.sh` and `ab-leg.sh` were **fatal** and are
now fixed to verify the modem and abort rather than emit mislabelled arms. *A
rule stated in prose is a wish; a rule in a script is a rule.*

**Next:** what terminates the suspend, given no edge is wake-armed. An
instrumented single suspend reading `pm_wakeup_irq` is running.

⏳ **COMPLETED, 2026-08-25 19:31 → 2026-08-26 00:45, `night-20260825-aba`** —
3 jobs, rc=0, 0 failed, guardian 905 lines with zero actions. Result above and in
the findings log; ☠️ leg A′ was **not** a control (modem down) and leg A's fitted
52.0 mA fails its own r² gate and must not be quoted. Original plan: The A-B-A
that measures item 1 on r76: leg A (radio up, nothing cut) → leg B
(`ModemManager rmtfs tqftpserv` cut) → leg A′ (control), one descent,
4 × 600 s cycles with a 600 s settle, recharging to 90 % between legs.
Preflight passed on all 14 gates. Guardian running. Two things to know before
touching the phone: **leg B leaves it unable to receive calls for ~100 minutes**,
and ☠️ **polling it during a leg invalidates the leg** (74 ssh logins cost
18.3 mA on 2026-08-25 and produced a clean trend that read like a modem effect).
Read the result from `journalctl -u night-queue` afterwards, not during.

★ Two things settled the same day that bear directly on this queue: an incoming
call **provably** raises the phone from s2idle and rings for 61 s (so the goal's
correctness constraint is met, not merely hoped for), and seven exclusions closed
without a single finding on the continuous-draw side. Both in TODO.

1. ★★★ **TOP — the MODEM LEAD.** The `vlow`/`vmin` deep-sleep item that stood
   here is **CLOSED 2026-08-24 night**: the raw message-RAM read
   (`power/bringup/tools/rpmstats_raw.py`) shows the RPM never enters `vlow`
   on the working UT oracle either (count 0 across a 10-min window with
   APSS +34 603 collapses and thousands of co-proc XO shutdowns) — the mode
   does not occur on this platform under any OS, the target was a phantom,
   the `smd-rpm.c` handshake plan is cancelled. Full account: findings-log
   2026-08-24 "(continued)"; the item's 300-line history: git log of this file
   + TODO-DONE.

   What remains of "deep sleep" is absolute draw, and its one proven lever is
   the modem: **modem processor off is worth ~36 mA** (79.1 → 43.3 mA asleep),
   mechanism unnamed, and every service-cut leg was contaminated by `rmtfs -P`
   (= modem shutdown). The ordered plan is in TODO "Deep sleep — CLOSED"
   section: (1) ✅ MPSS XO-duty across s2idle — DONE 2026-08-24: radio up =
   suspends abort early + MPSS chops the crystal; radio low = full-term
   suspends + MPSS XO off the whole window
   (`captures/2026-08-24_modem-xo-duty.txt`); (2) ✅ **(a) radio-low night slope leg
   DONE 2026-08-24 evening: 40.8 mA asleep** (phase-A −18.68 mV/h, r²=0.987,
   6/6 full-term suspends) against a 79–83 mA baseline and the 43.3 mA
   modem-off leg — **radio-low buys the whole ~36 mA without powering the
   modem processor off**; (b) the remoteproc modem-off leg is now optional;
   (3) **next: does a power-save mode that keeps the phone REGISTERED
   (PSM/eDRX/paging cycle) reproduce any part of it** — radio-low itself is
   airplane mode by another name, so it is a mechanism, not a fix. The fix
   direction is modem configuration, likely not an AP-side kernel patch.

2. ✅ **DONE 2026-08-23 night — rootfs freed 94%→81% and `10-health`
   recalibrated.** The bulk was the apk *download* cache: `/var/cache/apk`
   held 313 MB of old cached kernel `.apk` builds (r65–r74, ~30 MB each),
   redundant with the installed/unpacked kernel. Cleared with a plain
   `rm -f /var/cache/apk/*.apk` — **not** `apk`, so `world` was never
   re-resolved (the docs/deploy caution is specifically about `apk` mutating
   world; deleting cached downloads does not). Rootfs went 2.1 G→1.8 G used,
   128 MB→441 MB free, so journald is back above its 15% keep-free guard and
   the boot-before-last survives resets again.
   `tests/checks/10-health-test.sh` now has two tiers: FAIL at ≥98% (the old
   upgrade-hazard line) and a new **WARN at ≥85%**, where journald's default
   `SystemKeepFree` (15% of the fs, ~360 MB here) starts dropping older boots —
   so the instrument no longer prints a bare green `PASS: rootfs 93% used`
   while evidence is being deleted. The WARN line names the safe reclaim command.
   ☠️ **This refills on every kernel bump** (each `pmbootstrap` build re-caches
   the new `.apk`), so it is not a one-time fix — the WARN is the standing
   reminder to clear the cache when it fires.

3. **Price the WiFi lever in mA** (slope leg, `wlan0` down vs up). ☠️ PRONTO
   parks holding the XO when `wlan0` is down, so the naive reading flatters it.

4. ☠️☠️ **The camera wedges the phone and the watchdog resets it — and the
   fault is INTERMITTENT, about one camera-touching run in two.** This is not
   `99-suspend` failing, and it is not a `cpuidle` bug: the phone reaches
   `watchdog0: pretimeout event` because the camera cannot be torn down.
   Signature, every time:

   ```
   qcom-camss 1b00020.camss: VFE halt timeout
   qcom-iommu-ctx 1e34000/1e35000.iommu-ctx: timeout waiting for TLB SYNC   (x60-125, every 5 s)
   [sometimes] rcu: INFO: rcu_preempt detected stalls on CPUs/tasks
   watchdog0: pretimeout event
   ```

   ☠️ **Do not bisect this one run per arm.** A whole day was spent doing that
   on 2026-08-23 and it "cleared" four different arms; at a ~50% failure rate
   every one of those clearances was a coin flip, and all of them are retracted.
   Any arm-by-arm comparison needs several runs per arm and a stated rate.
   What is established, because it was observed rather than inferred:
   - `44-camera-af-windows` taking ~502 s rather than ~5 s is a **symptom** of an
     already-damaged camera, not a cause;
   - a `cci ... timeout` + `imx363 -110` fires at boot, ~13 s in, with no camera
     client in existence — [`TODO.md`](TODO.md) 33f-4, and it cuts
     against the client-collides-with-teardown story in 33f-2 and 33f-3;
   - the rate itself, ~3 wedges in 6 independent runs.
   ★★ **The hunt ran 8 passes and reproduced nothing — which is itself a
   result, and it corrects the rate I quoted.** Eight consecutive camera blocks,
   each from its own fresh reboot with the tap attached: **0 wedges, 0 fault
   lines**, boot id unchanged every time. Together with step G and both passes of
   step H that is **11 clean camera runs from fresh boots**. If the fault were a
   uniform coin flip, 0 of 11 would happen about 1 time in 2000. So ~50% is the
   rate *across all camera runs*, **not** the rate under these conditions, and
   the "about one run in two" phrasing above should be read that way.
   ☠️ **But do not turn that into "a fresh boot is safe" — that is exactly the
   inference this investigation keeps getting wrong.** What separates the arms is
   not established. The one *measured* difference is how long the phone had been
   up when the camera was first touched: the three wedges began at **290 s,
   1444 s and 2198 s** of uptime, every clean hunt pass at **~43 s**. That is a
   candidate, not a cause, and the 290 s case makes any threshold uncomfortably
   low. Other differences have not been excluded.
   **Next:** the hunt now takes a third argument, a settle time, so the same
   passes can be run after the phone has been up for a while — varying the one
   thing that actually differs.
   ☠️ **Second sighting of a smaller defect:** `98-camera-af-rail` finished with
   **no verdict at all** in 2 of the ~11 runs (hunt pass 8, step H pass 1). Before
   today's runner fix that scored as `ok`, so it has probably been happening for
   a long time unseen. Its detached mechanism is the suspect.
   **Instrument:** `docs/power/bringup/tools/camera-wedge-hunt.sh` — repeat the
   camera block from a fresh reboot, with `kmsg-tap.sh` streaming the kernel log
   to the **host**, and stop at the first fault, so the onset is finally captured.
   It has to go to the host because the phone's rootfs is 93% full and journald
   vacuums the boot before last (queue item 2): a reset destroys its own evidence.
   Full day-by-day account, including the three instrument errors it exposed:
   [`power/bringup/leads/camera-wedge-2026-08-23.md`](power/bringup/leads/camera-wedge-2026-08-23.md).

5. **The SSR write storm is a `qcom-ngd-ctrl` question, not a codec one.**
   Measured on r73: 78 lines of `Failed to write config eN` / `Failed to sync
   masks in 89`, spanning 36.46 s → 38.10 s, every one of them `-22` or `-12`,
   and they start *before* the codec is told anything — immediately after
   `HW wakeup attempt during SSR`. The controller accepts transfers while its
   own state is `DOWN` instead of failing them fast. Bounded and harmless now
   that the teardown ends it, so this is noise-removal, not a defect.
   ☠️ **The "no category" worry is retracted — it was wrong, and measured so.**
   `drivers/slimbus/qcom-ngd-ctrl.c` is *already* carried by two categories at
   once, on purpose: `wip/7.1.3/audio` has the QDSP6SS framer-bit commit and its
   revert (made to get the codec working), and `wip/7.1.3/power` has `implement
   disable_stream so the ADSP releases the channel` (same file, chased because
   LPASS would not sleep). The category follows **why** the change is made, not
   which directory it touches. This storm is SSR bring-up on the codec path, so
   it lands on **`wip/7.1.3/audio`** + `integration/7.1.3` + `debug-int/7.1.3`.
   ☠️ Found while checking that: **the branch table in `~/.claude/CLAUDE.md`
   lists five upstream-bound categories and there are seven.** `power` (8
   commits) and `i2c` (the QUP runtime-PM pinctrl fix) both carry real work and
   appear in neither that table nor `TODO.md`'s by-branch sections. Written
   up in [`TODO.md`](TODO.md); the table is incomplete, not
   authoritative — re-derive with `git for-each-ref`.
   The fix itself is still unwritten; the placement question is what is closed.

6. **Provoke the non-recovering SSR path** — needs a kernel-side hook now, so
   this is the one item here that is not a quick measurement. ☠️ Two dead ends
   are already recorded in [`TODO.md`](TODO.md), do not re-walk them: the
   `avs/audio` PDR route does not exist on msm8953 (`PDM: no support for the
   platform`), and holding audio traffic across a whole restart cycle moved the
   bring-up count by exactly one, not two. The reachable second source is
   `qcom_slim_ngd_notify_slaves()` on a runtime-PM resume taken while the
   controller state is `DOWN`, and that window closes as soon as the controller
   unregisters. Widening it deliberately is the next move.

7. ☠️ **Housekeeping item withdrawn — its premise is false.**
   `linux-postmarketos-qcom-msm8953` is **not installed**: `apk info` lists only
   `linux-fp3`. What does exist is a second module tree,
   `/lib/modules/7.0.9-postmarketos-qcom-msm8953`, and that one belongs to the
   **`postmarketOS-fallback` boot label** — the brick-safety net. Do not delete
   it. If `only one kernel release/flavor is supported` still appears on an
   `apk` run, it comes from the two module trees and needs a fix that keeps the
   fallback intact, not a package removal.
   ☠️ `apk del` on a package that is not installed reports a bare `1 error` and
   nothing else; `-v` is what makes it say why.

8. ★ **`base_dir` measured, and it was set on the wrong cache. Applied; the
   real verification is the next kernel bump.**
   Measured 2026-08-23 in the native chroot with a synthetic harness (same
   source, two absolute paths, `-g` and a differing `-I`), control shown hitting
   first so the harness is not blind:

   | configuration | hits |
   |---|---|
   | control, same path twice | **1 / 2** — harness works |
   | `hash_dir=true`, no `base_dir` | 0 / 2 |
   | `hash_dir=true`, `base_dir` set | 0 / 2 |
   | `hash_dir=false`, no `base_dir` | **0 / 2** |
   | `hash_dir=false`, `base_dir` set | **1 / 2** |

   So the changed absolute path really is what costs the hit, and `base_dir`
   recovers it — **but only together with `hash_dir=false`**, which the kernel
   cache already had. ☠️ **And `base_dir` was already present — on
   `cache_ccache_aarch64`, which the kernel build does not use.** The kernel
   compiles with x86_64-hosted cross tools, so its cache is
   `cache_ccache_x86_64`, and that one had `max_size`/`hash_dir` and no
   `base_dir`. Added `base_dir = /home/pmos` there (`builddir` is
   `$srcdir/linux-$_commit`, so `/home/pmos/build/src/linux-<hash>` changes
   every bump); the previous file is kept as `ccache.conf.bak-20260824`.
   ☠️ **Not yet verified on a real build** — a synthetic two-file harness is not
   a kernel. The measurement that settles it is `ccache -z` before the next
   `_commit` bump and `ccache -s` plus wall-clock after it. Until then this is
   "the mechanism is confirmed and the config now matches it", not "the hit rate
   improved".

   ★ **Partly settled during the r74 bump of 2026-08-23, and it turned up a
   second, larger defect.** `base_dir = /home/pmos` and `hash_dir = false` are
   confirmed present in **both** `ccache.conf` files, so that fix is in place.
   ☠️☠️ **But the recorded "raised to 25G" was false and had never taken
   effect.** Measured mid-build: `ccache -s` reads `Cache size (GB): 5.0 / 5.0
   (99.94%)` with **5062** cleanups, and both config files read literally
   `max_size = 5G`. The cache has been evicting continuously the whole time,
   which is exactly the condition the `base_dir` work was meant to stop
   mattering. Raised to 25G for real (`sudo`, read back from both files;
   ☠️ an unprivileged `sed -i` fails on this root-owned tree with a *temp-file*
   permission error that is easy to skim past as noise). 398 G free on the
   volume, so the size is not a constraint.
   ☠️ **The lesson is about this document, not about ccache: a note saying a
   thing was fixed is not evidence that it was.** Read the config back.
   Hit rate at the time of measurement, for the next comparison: 60.30 %
   (622 829 / 1 032 922 cacheable calls).

**Waiting on a human, skip over them:**

- the call-wake ↔ deep-sleep trade has to be *decided* (inhibitor while ringing,
  or conditional arming), not measured further
- the wake-arm unit's default, the WiFi suspend policy, and the fate of the three
  experiment knobs (`clk_smd_rpm.xo_sleep_off`, `qcom_smd_regulator.both_sets`,
  `icc_smd_rpm.sleep_init` — all default OFF)
- the USB-detached combined session (rail census, slot switch to the UT oracle)
- sending `smd-wake-v1` to the LKML

## Guardrails that have each cost a day

- **`pkill -f` / `pgrep -f` match your own command line — and this bit again on
  2026-08-23.** A cleanup `pkill -f 'kmsg-tap.sh'` was written at the front of
  the same command that then started the tap and ran the battery; the pattern
  matched that command line, so the job killed itself before doing anything
  (exit 144) and the measurement had to be repeated. This guardrail was already
  written down. Kill by **explicit PID** from `ps -eo pid,args`, or give the
  pattern something the killer's own line does not contain.
- **A reboot's witness is `uptime` compared against elapsed time, not `uptime`
  alone.** Measured 2026-08-23: a run started at uptime 951 and ended at 1242, so
  the number rose and I called it "no reset" — but the run itself took ~2000 s,
  so an un-reset device would have read ~2950. Record the host-side start and
  end and require `uptime_after >= uptime_before + elapsed`.
- **A killed run can poison the next one.** Same day: a battery left in the
  foreground past a 10-minute cap was killed mid-camera-test and left the camss
  wedged; the next run inherited it and its result was uninterpretable. Before
  trusting a run, check that the kernel log's **first fault is later than the
  run's start**. Long runs go in the background, never the foreground.
- **An excerpt you wrote is not evidence about the boot it came from.** A claim
  that two earlier boots "contained no camss line" rested on capture files that
  were my own selections; the boots had since been vacuumed and it could not be
  rechecked. Grep the source, or write it down as unknown.
- **The category rule.** A kernel change lands on `wip/<base>/<category>` **and**
  `integration/<base>` **and** `debug-int/<base>`, then all of them are pushed to
  `fork`, and only then does `_commit` move.
- **Tarball check before the build:** `curl -sL -o /dev/null -w '%{http_code}'`
  on the pinned commit must be **200**, and the same command on a bogus hash must
  be **404** — a verifier not yet shown failing has proved nothing.
- **`apk add` first with `--simulate`,** read the output for `Purging`.
- **`apk add` rewrites `extlinux.conf`.** Re-arm it afterwards and check the md5;
  the backups live next to it in `/boot/extlinux/`.
- **One `pmbootstrap` command at a time.**
- **A reboot is witnessed by `uptime`, never by a return code.** Use
  `systemctl reboot`; a backgrounded `reboot` over ssh dies with the session.
- ☠️ **remoteproc indices move between boots.** Address by name or platform
  address (`grep -l 4080000 /sys/class/remoteproc/*/name`), never by index.
- ☠️ **Never run two destructive measurements at once**, and never trust a
  waiter built on `pgrep -f` — it matches its own command line and never exits.
- ☠️ **GitHub answers `429` to the tarball check when it is rate-limited**, and
  it answers it for the bogus hash too. Measured 2026-08-23. A `429/429` pair is
  **not** a pass and not a fail — it is the check refusing to answer. Retry
  until the bogus hash reads `404` again, and only then read the real one.
- ☠️ **A blank row is not a zero.** A debugfs sampler that runs as the user
  prints *empty* lines for `/sys/kernel/debug/qcom_rpm_master_stats` — root-only
  — and they read as "nothing to see" next to lines that do print. Gate every
  sampler on being able to read each of its sources, and show each gate aborting
  before believing any row.
- ☠️ **`./pmb build` outlives a 10-minute tool timeout badly.** Run it detached
  and poll, rather than letting the harness kill the shell mid-compile.
