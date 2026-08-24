# The camera wedge and the watchdog resets — investigation log, 2026-08-23

> ⚠️ **AI-generated.** Written by Claude working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on.

**This is a dated log, not the current state.** The live item is queue entry 5
in [`STATUS.md`](../../STATUS.md); read that first. This file exists because the
investigation reversed itself several times in one day, and each reversal is
worth more than the conclusion it replaced — three of the mistakes below were
instrument errors that would otherwise be repeated.

☠️ **The headline correction, if you read nothing else:** the fault is
**intermittent**, roughly one run in two. Every "this arm is clean" result in
this log is a single non-reproduction and therefore proves nothing. The
localisations were retracted on the same day they were made; the *measurements*
and the *instrument fixes* are what survive.

What survives, in one place:

- The failure signature is `qcom-camss ...: VFE halt timeout` followed by a
  `qcom-iommu-ctx ...: timeout waiting for TLB SYNC` storm at 5 s intervals,
  sometimes with an `rcu_preempt` stall, ending at `watchdog0: pretimeout event`.
  The debug layer's watchdog is doing its job; the camera cannot be torn down.
- `44-camera-af-windows` taking ~502 s instead of ~5 s is a **symptom** of an
  already-damaged camera, not a cause. It was read as a duration for hours.
- A `cci ... timeout` + `imx363 ... -110` fires **at boot**, ~13 s in, with no
  camera client in existence — see `TODO.md` 33f-4.
- Roughly 3 wedges in 6 independent camera-containing runs.

☠️ **A fourth instrument error, caught on the first pass of the hunt itself.**
The hunt counted faults with `grep -cE ... || echo 0`. `grep -c` prints `0` when
nothing matches **and** exits 1, so the `|| echo 0` fired too and the variable
became two lines; the later `[ "$after" -gt "$before" ]` then errored on a
non-integer and returned non-zero — which reads exactly like "no wedge". The
detector could never have fired. It was visible only as a stray `0` in
`summary.txt`. Shown failing before the fix (`od -c` gives `0 \n 0`, the
comparison fails) and shown working after (0 on a clean tap, 136 on a wedged
one, comparison succeeds).

The blow-by-blow follows, in the order it happened.

---

5. ☠️☠️ **The phone HANGS and the watchdog resets it — `99-suspend` was never
   the problem.** This item used to read "fix the check, not the kernel". That is
   **retracted**: measured 2026-08-23 on r73, the battery's detached tail
   (`98-camera-af-rail`, `99-suspend`) does not fail, it **dies with the
   device**. The boot before the current one ends with

   ```
   rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
   ...  pc : cpuidle_enter_state+0xb8/0x740
        cpuidle_enter / do_idle / cpu_startup_entry / secondary_start_kernel
   watchdog0: pretimeout event
   ```

   — the RCU grace-period kthread's CPU stuck inside `cpuidle_enter_state`, and
   then the debug layer's watchdog resetting the phone. `journalctl
   --list-boots` shows the reboot landing mid-run. **The safety net worked;** the
   check's "no verdict was written" and the `run-detached.sh: no such file` that
   follows are both just `/tmp` being tmpfs on a machine that rebooted.
   Capture: `docs/power/bringup/captures/2026-08-23_rcu-stall-cpuidle-watchdog.txt`.
   ☠️ **Also retracted:** this page previously explained the same 606 s hang away
   as "a boot that had had an ADSP restart, did not reproduce on a clean boot".
   It has now reproduced on a boot with no manual ADSP restart.
   ★★ **Two instances confirmed now.** A second full battery, run alone, reset
   the device again — uptime 1667 s before, 356 s after — and its dead boot ends
   the same way: `rcu: INFO: rcu_preempt detected stalls` at monotonic 2398.8 s
   (`t=5252 jiffies, g=213625, q=2286 ncpus=8`), then `watchdog0: pretimeout
   event` at 2417.8 s, with nothing logged in between. Capture:
   `captures/2026-08-23_rcu-stall-second-instance.txt`. So it reproduces on the
   full battery and not on the two checks alone — **2 of 2 full runs, 0 of 3
   isolated runs**.
   ☠️ **Localisation, and a wrong reading of mine corrected:** the interleaved
   `ssh: Connection refused` lines start next to `60-wifi`, which looked like an
   early reset. It is not — those are the detached check's own polling. The
   monotonic timestamps put the stall ~750 s into the run, i.e. inside
   `98-camera-af-rail`'s detached phase, matching the first instance.
   ☠️ **Tried, and it does not reproduce in isolation.** `--only
   camera-af-rail,suspend`, three consecutive runs: **2 ok / 0 failed each time,
   no reset** (uptime monotonic 1299 → 1331 → 1362 → 1398 s). So the hang is
   **load-dependent** — it needs the rest of the battery ahead of it, not just
   these two checks. ★★★ **Step B reproduced the reset, and the kernel named the subsystem this
   time — the "cpuidle hang" framing is now too narrow.** Dropping the *first
   half* of the pre-camera checks (01-identity … 25-sensor) and keeping the
   camera block **still reset the device** (uptime 2198 → 27). So checks 01–25
   are not part of the load, and with step A that brackets it to the camera
   block. The dead boot contains **no RCU stall at all**
   (`grep -c 'rcu_preempt detected stalls'` = 0) — it is a *different* failure
   mode reaching the same watchdog, and until something links them the two must
   not be called one bug. The chain, monotonic, the run having started at 2198 s:

   ```
   [2260.16] i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout
   [2260.16] imx363 0-001a: Error reading reg 0x0016: -110
   [2319.92] qcom-camss 1b00020.camss: VFE halt timeout
   [2324.94] qcom-iommu-ctx 1e34000.iommu-ctx: timeout waiting for TLB SYNC
             ... 60 TLB SYNC timeouts + 5 VFE halt timeouts over 518 s ...
   [2859.02] watchdog0: pretimeout event
   ```

   The first fault is **62 s into the run** — inside `42-camera-flash` /
   `43-camera-manual-focus`, **not** in the detached tail where the earlier
   localisation put it. The phone then spends ~10 minutes unable to tear the
   camera down. Capture:
   `docs/power/bringup/captures/2026-08-23_camss-iommu-wedge-watchdog.txt`.
   ★ **This is nearly the known item [`TODO.md`](TODO.md) 33f-2**, which
   already records the same `master 0 queue 0 timeout` + `-110` from touching the
   camera while another client tears it down. Two differences: 33f-2's `-110` is
   on the ak7375 **lens**, this one is on the imx363 **sensor**; and 33f-2's
   consequence is bounded (AF disabled for the boot, streaming continues) while
   this one wedges the IOMMU and resets the phone. Same first link, worse ending
   — so the next move is against **concurrent CCI access during camera
   teardown**, not against cpuidle.
   ☠️☠️ **A defect in our own instrument, found in the same log: a dead phone
   reports green.** After the reset the runner printed `ok:` for **nine** checks
   (`50-charger` through `71-clock`), each with empty output, each immediately
   after `ssh: connect to host 172.16.42.1 port 22: No route to host`. A check
   whose transport fails is being scored as a pass. Every "N ok" from a run that
   reset is therefore worthless after the reset point — including, by the same
   rule, any future bisect step. Step A is unaffected: it did not reset.
   ★ **FIXED and both directions shown, 2026-08-23.** `tests/fp3-selftest` now
   keeps ssh's exit status (the `|| true` was throwing it away) and requires a
   verdict: a check whose output has no `PASS:` and no `FAIL:` line is scored
   **FAIL — no verdict**, with the reason distinguishing an unreachable device
   (ssh rc 255) from a check that exited non-zero from one that simply printed
   nothing. A no-verdict check no longer marks its category covered either.
   Shown failing: a temporary check that emits nothing scored
   `FAIL: 97-noverdict (1s) - no verdict: the check produced no PASS: or FAIL:
   line`, where the old code would have printed `ok:`. Shown passing:
   `ok: 71-clock (1s)` on the same build.
   ★★★ **Step C, and three corrections it forced.** Ran `--only camera,suspend`.
   ☠️ **First I read it as "no reset" and that was wrong.** uptime went 951 →
   1242, rising, so I called it monotonic — but the run lasted ~2000 s, so an
   un-reset device would have read ~2950. **uptime-after > uptime-before is not
   evidence of no reset; it must be compared against the run's elapsed wall
   time.** Added to the guardrails below.
   ☠️ **Second, the run is confounded, by my own earlier mistake.** That boot's
   first fault is at 541 s and step C only started at 951 s: the camera was
   already wedged, left that way by a previous attempt at the same run which I
   killed by leaving it in the foreground past a 10-minute cap. So step C says
   nothing about its own contribution. What it does support is that a
   camera-block-only run started the wedge unaided (the killed attempt did, ~4
   min in), and that the wedge survives into a later run and ends in a reset
   19 minutes on. **Before trusting a run, check the kernel log's first fault is
   later than the run's start.**
   ★★ **Third, the two failure modes are linked after all — and CCI is not
   required.** That single boot carries **both**: 125 `TLB SYNC` timeouts, 9
   `VFE halt timeout`, **and** an `rcu_preempt detected stalls` (CPU 5, 1 GP
   behind) 1131 s after the storm began, then `watchdog0: pretimeout`. So the
   step-B insistence that these are two unrelated bugs is withdrawn; a CPU
   spinning in a 5 s IOMMU timeout loop stalling RCU is a plausible mechanism,
   but that is a hypothesis, not a measurement. The same boot has **zero** CCI
   timeouts and zero `-110`, so step B's CCI timeout is **not necessary** to
   reach the wedge. The common core across every reset so far is **VFE halt +
   TLB SYNC storm**.
   ☠️ **Retraction of my own step-B sentence:** I wrote that the two earlier
   resets "contain no camss or IOMMU line at all". That came from excerpt files
   I had written myself, not from the boots, and the boots are gone. Unknown, not
   false — but it was never measured.
   Capture: `docs/power/bringup/captures/2026-08-23_camss-wedge-step-c-confounded.txt`.
   ★ The no-verdict guard added an hour earlier caught a **real** case here, not
   a synthetic one: `FAIL: 45-camera-af-windows-pipewire (74s) - no verdict: the
   device was unreachable`, where the old runner printed `ok:`.
   ★★★ **Step D settles it: the camera block alone resets the phone.** Run
   `--only camera,suspend` from a boot verified clean beforehand (zero `TLB
   SYNC` / `VFE halt` / `cci` / `rcu_preempt` lines in `dmesg`), and scored by
   the new rule: `uptime_before=1444`, `uptime_after=1233`, elapsed **1922 s**,
   so an un-reset device would have read ≥3366. **Reset.** The shape repeats
   exactly across all three camera-containing runs: `43-camera-manual-focus`
   fails, `44-camera-af-windows` passes after ~502 s, and the device goes away
   during `45-camera-af-windows-pipewire`. So neither the audio checks, nor
   `30-voice`/`35-pulse`, nor the charger/wifi/modem tail are needed — the
   camera block is sufficient on its own, and the earlier "0 of 3 isolated runs"
   result stands only because those runs were `--only camera-af-rail,suspend`,
   i.e. checks 98 and 99 **without** 40–45.
   ☠️☠️ **And there is no kernel evidence for it, because the journal was
   vacuumed.** `journalctl -k -b -1` on the resulting boot answers `-- No
   entries --`. Item 3b is therefore **blocking, not cosmetic**: the failure can
   be reproduced at will and not characterised.
   ★ **Fixed by moving the log off the device**, not by freeing space:
   `docs/power/bringup/tools/kmsg-tap.sh` streams `dmesg -w` to a file on the
   **host**, reattaching after a reset (and `dmesg -w` replays the ring, so the
   new boot is captured from its start too). Shown working — 1092 lines captured
   live — and shown failing — pointed at an unroutable address it writes
   `=== detached ... link lost or device reset, retrying` rather than sitting
   silently.
   ★★ **Step E clears the prime suspects and moves the blame earlier.** Ran
   `--only camera-af-windows` (checks 44 and 45 **alone**) from a fresh reboot,
   with `kmsg-tap.sh` attached: **PASS — 2 ok, 0 failed**, no reset (uptime 45 →
   84 across exactly 39 s of wall time), and **zero** `TLB SYNC`, `VFE halt` or
   `rcu_preempt` lines in the tapped kernel log. So 44/45 are not the cause.
   ★ **And the timing gives the mechanism away:** `44-camera-af-windows` ran in
   **6 s** here against **502 s** every time it ran inside the full camera
   block. It is not slow by nature — it is slow because something before it has
   already damaged the camera. The 502 s was a symptom being read as a duration.
   That points at checks **40–43** (enumeration, focus, flash, manual focus) as
   the ones that do the damage, which is consistent with `43-camera-manual-focus`
   failing in every camera-block run and passing in the one run where it went
   first.
   ★★ **Step F clears 40–43 as well, so neither half reproduces alone.** Checks
   40, 41, 42, 43 from a fresh reboot with the tap: **PASS — 4 ok, 0 failed**, no
   reset (uptime 166 → 231 across exactly 65 s), zero faults in the tapped log.
   And `43-camera-manual-focus` took **3 s and passed** here, against 82–126 s
   and failing every time it ran inside the camera block.
   So: 40–43 alone fine, 44–45 alone fine, 40–45 together wedges and resets.
   ☠️ **A confound I only saw when the halves both passed:** the runs where 43
   failed did **not** start from pristine boots. Step D began at uptime 1444 on a
   boot that had already carried step C's detached `98-camera-af-rail` tail, and
   I had cleared that boot only by grepping `dmesg` for *fault* lines — which
   says nothing about whether the camera had been exercised. "No faults yet" is
   not "untouched". The reproductions so far therefore vary in **two** things at
   once, check composition and prior camera activity in the boot, and cannot
   separate them.
   ★★★ **Step G settles it: the camera block is not the trigger — a second
   camera session in the same boot is.** The whole block plus suspend, from a
   verified fresh reboot with the tap: **no reset**, boot id unchanged,
   **zero** `TLB SYNC` / `VFE halt` / `rcu_preempt` lines, and the tell-tale
   timings back to normal — `44-camera-af-windows` **5 s** (not 502) and
   `43-camera-manual-focus` **3 s** (not 82–126). The one failure,
   `42-camera-flash`, is the ambient-light comparison and unrelated.
   So every earlier reproduction had one thing in common that step G removed:
   **the camera had already been used earlier in that boot.** That is the
   variable, not which checks are in the set — and it fits `33f-2`, where each
   camera creation adds another ancillary media link instead of replacing one.
   ☠️☠️☠️ **Step H refutes step G's conclusion, and with it the whole bisect
   method used today.** Two full camera blocks back to back on one fresh boot:
   **both passed**, same boot id throughout, zero faults. So "a second camera
   session in the same boot" is **not** the trigger either.
   And the run that breaks the story was already in hand: the attempt at step C
   that I killed had started ~4 minutes into a nearly-fresh boot, with nothing
   before it, and it **did** wedge — same command line as step G, which passed.
   **The fault is intermittent.** Counting independent camera-containing runs
   today: wedged in step B, in the killed step-C attempt, and in step D; clean in
   step G and in both passes of step H — roughly **3 in 6**.
   ☠️ **Therefore steps E, F, G and H "clearing" things clear nothing.** Every
   one of them is a single non-reproduction of a fault that fails about half the
   time, so each had a coin-flip chance of looking innocent. I wrote as early as
   step A that "a single non-hanging run is weaker evidence than the two hangs it
   is compared against" and then spent the afternoon reasoning as though the
   fault were deterministic. **Retract the localisations, keep the measurements.**
   What survives, because it was observed rather than inferred:
   - the failure signature — `VFE halt timeout` plus an `iommu-ctx ... TLB SYNC`
     storm at 5 s intervals, sometimes with an `rcu_preempt` stall, ending at
     `watchdog0: pretimeout event`;
   - `44-camera-af-windows` taking 502 s instead of 5 s is a **symptom** of an
     already-damaged camera, not a cause;
   - the boot-time `cci ... timeout` + `imx363 -110` at 13 s with no client
     present (`TODO.md` 33f-4);
   - the reproduction rate, ~50% per camera-containing run.
   Next, and it is a different kind of job: **stop bisecting and go for the
   mechanism.** Loop the camera block on fresh boots with `kmsg-tap.sh` attached
   until it wedges, which at ~50% should not take many passes, and read the
   onset out of the host-side log — the one thing no reproduction so far has
   produced. Only after that does arm-by-arm comparison make sense, and then
   only with several runs per arm rather than one.
   ☠️ **The reset guard added earlier was wrong and is now fixed.** Comparing
   uptime against elapsed wall time cannot work on this battery: `99-suspend`
   suspends the device on purpose and suspended time does not accrue, so step G
   lost 35 s with no reboot at all. A long enough suspend would have made it cry
   reset on a healthy run. It now compares **`/proc/sys/kernel/random/boot_id`**,
   which changes on reboot and on nothing else, and reports the uptimes only as
   context. Shown failing: rebooting the phone deliberately 25 s into a run now
   prints `DEVICE REBOOTED DURING THIS RUN: boot id 7c63d1ca… -> e955f2b9…` and
   fails the run.
   ☠️ **A second hole, found while proving the first fix and also closed:** that
   same deliberate reboot initially still reported `PASS - 1 ok`, because the
   check had emitted a `PASS:` line before the link died and the reboot could
   not be confirmed afterwards. The runner now waits for the device to come back
   before deciding, and if it still cannot tell, **fails** — an unattributable
   run is not a green one.
   (`--skip` the tail, then progressively fewer), each time checking `uptime`
   for a reset, until the smallest prefix that still hangs is known. Budget it
   as a long unattended run; each iteration costs a reboot when it hits.
   ☠️ **Harness trap, mine:** never run two batteries overlapping — killing the
   first fires its cleanup trap, which deletes `/tmp/fp3-selftest` out from under
   the second and produces exactly this "vanished helper" signature for
   an unrelated reason.