# Open items

> Closed sections and items are moved verbatim to [`TODO-DONE.md`](TODO-DONE.md);
> numbering gaps here are deliberate so references by number still resolve.

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

Things that are known-broken, deliberately unfinished, or parked with enough
context to pick up later. Each entry says what was measured, not what was
guessed. Items that are already written up elsewhere are linked rather than
repeated.

> ☠️ **If the phone will not boot, the recovery route is not in this file.** It
> is `fp3-kernel-test`'s `references/recovery.md` (method), and the last time it
> was needed is written up in [`TODO-DONE.md`](TODO-DONE.md) under "r74 does not
> boot" (what happened). The one-line version: `fastboot set_active a` boots
> Ubuntu Touch, from which pmOS's embedded `/boot` mounts with
> `losetup -o 1048576 /dev/mmcblk0p31`. ☠️ `fastboot boot` does nothing on this
> bootloader, and the lk2nd menu is unusable because the screen stays black —
> do not plan around either.

## A sor — mi a következő

> Ez a **munkasor**: rövid, gépi és ez az egyetlen forrás. A hook
> (`plugins/fp3/hooks/queue.cjs`) ezt olvassa, és mást nem tart nyilván. Alatta a
> lap többi része **dosszié**, nem feladatlista — oda a mérés és az indoklás megy.
>
> Jelölések: `[ ]` mehet · `[~]` a sessionön kívül várakozik · `[@]` emberre vár ·
> `[x]` kész (innen a [`TODO-DONE.md`](TODO-DONE.md)-be költözik).
> Kulcsok: `after:` előfeltétel · `until:` mikor él újra · `when:`/`they-do:`
> emberi tételnél · `why:` egy sor, hogy miért ez a feladat.
>
> ☠️ **Az ütemezés kulcs, nem próza.** „PARKOL, a 116. mögé" némán elavul és
> senki nem olvassa újra; egy `after: 116` minden feldolgozáskor ellenőrződik.

<!-- FP3-QUEUE:BEGIN -->
- [ ] 50. SMSM PROC_AWAKE (12. bit) — az orákulum bootkor 1-re állítja, mi soha
      why: az EGYETLEN nyitott tétel, ami LKML-patchet termel; kell mellé egy eszköz-oldali igazoló mérés a commit-üzenetbe, NAPPALI slotban (ne csússzon össze a 116. orákulum-sessionnel)
- [ ] 82. Kapu-napló és felülvizsgálati dátum minden kemény kapuhoz
      why: asztali munka, telefon nélkül; a kapu-rothadás ellen véd — minden kapu hordozzon incidens-linket és lejáratot
- [@] 63. Elérhetőség-teszt: óránként egy hívás nappal
      when: óránként nappal; a reggeli sarok-minta CSAK mérés nélküli éjszaka után
      they-do: óránként egy hívás, kicsöngetve, felvétel nélkül — jelenteni nem kell semmit. ☠️ MA ESTE NE: 19:00-tól a telefon mér, a rádió-ki ablakokban jogosan nem csöng
      why: a csöngés az EGYETLEN elfogadható kapu; a CS-attach/SGs csak prediktor
- [@] 112. Ránézés a napi, gyári Androidos FP3 státuszsorára hívás közben
      when: a következő nappali hívásnál
      they-do: a HÍVÓ készüléken nézd meg, LTE/4G marad-e (VoLTE/HD ikon), vagy 2G/E/G-re vált a hívás idejére. Egy szó a válasz. ☠️ A napi telefonhoz egyébként nem nyúlunk
      why: gyors elő-szűrő a második kapura — ha egy tanúsított készülék is CSFB-zik, az imsd-út ezen a hálózaton értelmetlen
- [~] 85. Replikáció 3 booton + OCV-vs-QG
      until: 19:00
      why: ez adja a 40,3 mA boot-közti hibasávját és a kalibrációs offset-korlátot; eszközoldali timer indítja (fp3-night-start.timer), ellenőrizve
- [~] 118. Az éjszakai mérleg kiértékelése az előregisztrált sávok ellen
      after: 85
      why: a reggeli triázs; a night-budget.py és a sávok készen állnak
- [~] 79. Sönt-kalibráció — az egyetlen tanú, ami nem a PMI632-n megy át
      until: 09-04 10:24
      why: nem blokkol, hanem erősít: a lezárás kimondható a |ε| ≤ 1,49 (δ + I·|g|) korláttal is
- [~] 72. Küszöb-idő módszer (kalibráció nélküli áram-arány)
      after: 85
      why: feltételes tartalék — csak akkor él, ha az esti OCV-párból számolt |ε| korlát nem elég szoros
- [~] 75. Ki írja vissza: ModemManager --log-level=DEBUG drop-in
      after: 85
      why: egy reboot, nulla kockázat — de a következő úgyis-reboot UTÁN, mert a debug-naplózás a ma esti lábakat szennyezné
- [~] 81. Mérés-indító wrapper (fp3-measure), gép-szintű zárral
      after: 85
      why: a mai PreToolUse-kapu csak a saját sessionömben fut; egyetlen belépési pont zárná a több-gép- és a kézi-ssh-lyukat is
- [~] 124. A QG nyers számláló kitétele mainline-ra (CHARGE_COUNTER)
      after: 85
      why: docs/TODO.md kimondja kérdésként, de nincs mögötte tétel; a driver a mért rendszer része, ezért csak a replikáció után
- [~] 116. A döntő tanú a készülék-policy kapujára: UT-orákulum slot, azonos IMEI
      why: EZ A HORGONY — egy orákulum-session, egy csekklistával; hat tétel áll mögötte
- [~] 55. Attach-PDN lista mindkét sloton
      after: 116
      why: a 116. orákulum-session 2. sora
- [~] 54. DIAG OTA-capture az orákulum sloton (RRC cause + NAS/ESM típusok)
      after: 116
      why: a 116. orákulum-session 3. sora
- [~] 41. A következő slot-váltás: sáv-illesztett orákulum-mérés, nem pref-olvasás
      after: 116
      why: a 116. orákulum-session 4. sora
- [~] 64. A „miért bont" — egyetlen, határolt ~30 perces IMS/QIPCALL capture
      after: 116
      why: a P-CSCF-lelet óta ez nem dönt el semmit, amíg a 116. ki nem mondta, hogy az imsd-út egyáltalán él; ☠️ a DIAG-folyam némasága külön akadály
- [~] 19. A′ kontroll a bearer-karra (bearer lebontva, minden más azonos)
      after: 116
      why: az imsd-jövő árazása
- [~] 30. A bearer-kar újramérése sáv-lockkal
      after: 116
      why: az imsd-jövő árazása; a mai mérés sávja nem volt rögzítve
- [~] 31. A sáv-preferencia mint szállítható kar
      after: 30
      why: lezárás utáni tétel — a cél a duplázás lezárása, nem a minimum megtalálása
- [~] 53. A modem saját története (modem-story infrastruktúra)
      after: 85
      why: megértés-infrastruktúra; az újraírt célfüggvény nem fizet érte — lezárás után újranézni, vagy elejteni
<!-- FP3-QUEUE:END -->

## Where this stopped, 2026-08-25 — read this first after a long gap

☠️ **The version of this section dated 2026-08-14 was still here on 2026-08-20 and
every load-bearing sentence in it had gone false.** It said the application
processor had *never once* told the RPM it was going down, that its shutdown count
was zero, and that "that single zero explains the rest". The count is now **16 991
after ten minutes of uptime**, the zero was fixed on 2026-08-17 by one hex digit,
and `vlow` is *still* 0 — which is precisely the sentence the old section used to
rule out. A "read this first" paragraph that is wrong is worse than no paragraph;
that is why this one now carries its own date in the heading.

**Update 2026-08-22: the PLL enable-failure item below is closed** — v2 fix
(global `cpu_latency_qos` from the clk notifier), measured 27 720 transitions +
24 916 power-collapse entries with 0 failures; the section moved to
`TODO-DONE.md`, post-mortem in `power/bringup/findings-log.md` (Part II).

☠️ **Update 2026-08-25: that v2 fix was itself one of the two biggest wakers on
the phone.** Correct as a *correctness* fix — zero PLL failures, and that still
holds — but the global `cpu_latency_qos` it took barred **both** clusters from
power collapse on every relock: 45.8 pm_qos updates/s and 128 IPIs/s on a 96 %
idle phone, two thirds of all IPI traffic. Replaced by a cluster-local cpuidle
hold (`wip/7.1.3/power` `68dcadbd`, shipped as r76); measured after, pm_qos
458 → 0 per 10 s with the failure count still zero. The lesson is in the shape,
not the patch: **a fix measured only against the fault it targets is half
measured.**

**The device is on `linux-fp3-7.1.3-r76` (`#77-fp3`, `debug-int/7.1.3`
`5aafd59e`), and the running kernel is ours.** ☠️ Read off the device
2026-08-25; the previous revision of this line said `r73` / `#74-fp3` /
`818d35f1`, which is the **fifth** time this exact paragraph has gone stale —
it has now named `r61`, `r65`, `r70`, `r73` and `r76` in turn. Do not read the
revision off this page at all; read it off the device.
`/boot/vmlinuz` matches the file owned by that package byte for byte.
☠️ **This line is the one that goes stale first** — two earlier revisions of this
paragraph named `r61` and `r65` while the phone had long moved on, so read the
package version off the device (`apk info -vv | grep linux-fp3`, `uname -v`)
before trusting it.
☠️ `uname -r` reads `7.1.3-postmarketos-qcom-msm8953`, which looks like the
upstream flavour and is not: the package's own `kernel.release` says so, while its
flavour directory is `fp3`. **But `linux-postmarketos-qcom-msm8953-7.1.3-r0` is
also installed**, owns no `/boot/vmlinuz`, and is what makes every `apk` run end
with `only one kernel release/flavor is supported`. Removing it is housekeeping
nobody has done.

**The one thing worth working on is still idle current, and it is still a platform
gap — but a different one.** Three of the four gates now open:

| gate | state |
|---|---|
| the cores reach `cpu-power-collapse` | ✅ since the genpd `bool` fix |
| the AP tells the RPM it went down | ✅ since `0x42000353`, and it does it thousands of times a minute |
| the audio DSP shuts down | ✅ reachable — an ADSP restart frees it for the rest of the boot |
| **the RPM enters `vlow` / `vmin`** | ✅ **CLOSED 2026-08-24 — it never does, on ANY OS: the raw message-RAM read shows count 0 on the working oracle too. Not a gate; the mode does not occur on this platform** |

☠️ **There is no `deep` on this platform.** `mem_sleep` offers `[s2idle]` only, and
s2idle itself works — 6/6 suspends, full duration. "Deep sleep" here means getting
the RPM into `vlow`, not finding a suspend mode that does not exist.

**Where the numbers stand (r76, 2026-08-25 — the r73 figures this replaces are
kept in brackets so the movement is visible):** awake, panel off, **median
98.3 mA** [was 148–157] with the **floor unchanged at 52.9** [54] · asleep, no
cuts, 79.1 mA · asleep with the modem stack cut, 43.3 mA · asleep with the ADSP
collapsing, 70.8 mA. The three sleeping figures are r73-era and are what
tonight's A-B-A re-measures on r76.

☠️ **Read the shape, not just the number.** The r76 win is entirely in the
bursts — median down 35 %, floor flat — which is exactly what wakeup fixes
predict and exactly what a *continuous-draw* fix does not. Burstiness (median ÷
floor) went 2.75× → 1.86×, against the oracle's 1.97×, so pmOS now bursts
**less** than UT. **The floor is the whole remaining problem**, and nothing
found so far moves it.

**What closed on 2026-08-19/20, so nobody re-runs it:** that an ADSP client holds
LPASS (six stages, up to stopping the DSP — nothing moved); that the regulator
sleep-set costs anything droppable here (five suspect rails became one with USB
unbound, and that one is the eMMC's); that USB stops the DSP collapsing (three
alternating rounds, nothing); and that the held ADSP session is the lever (the leg
prices it at ~4 %, inside the instrument's own spread). Full account in
[`power/bringup/leads/lpass-never-sleeps.md`](power/bringup/leads/lpass-never-sleeps.md)
and [`power/bringup/findings-log.md`](power/bringup/findings-log.md).

**So the next question is the modem lead** — the one thing that has *ever*
moved the sleeping number (~36 mA when the modem processor is off), mechanism
still unnamed; see the "Deep sleep — CLOSED" section below for the ordered
plan. Not the ADSP, and not the RPM mode counters (closed 2026-08-24).

☠️ **The 139–143 mA floor and its daemon subtraction are retracted** — the lens
actuator was powered underneath the whole run. The `ak7375` kernel fix that was
queued as "the cheapest next step" shipped long ago. What remains there is
userspace — nothing returns the lens to rest when the preview stops.

**Two lines of work were deliberately stopped, not abandoned.** Both are written
up so they need no re-investigation:

* the fuel gauge's `.resume_early` rest anchor — written, measured working,
  [parked as a patch](charger/bringup/parked/README.md) because it is a
  workaround for an unreachable precondition, and the `S3_GOOD_OCV` path it
  substitutes for is already in the driver and merely starved;
* automatic sleep — demonstrated working, then switched back off because an
  incoming call could not wake the phone. **The wake side is fixed and
  call-proven as of 2026-08-22 (r66, see the next section), and on 2026-08-25
  the whole ring-through was proven end to end on r76**: one controlled
  suspend, the phone woke on the call 113.6 s into a 420 s RTC backstop and
  **rang for 61 seconds**. That answers the ringing-inhibitor half by
  observation — something does hold suspend off for the duration of the ring,
  so it need not be built, only identified. What remains is the first half: a
  **persistent way to arm the modem edge at boot** (the knob defaults to off,
  by design, and was armed by hand for that test). Until that exists, automatic
  sleep must not be switched back on — an unarmed edge is the 2026-08-14 state,
  where the call reaches the modem and the AP never wakes.

## ☠️ The camera wedges the phone and the watchdog resets it — intermittently

**Live item: queue entry 5 in [`STATUS.md`](STATUS.md). Day-by-day account with
every reversal: [`power/bringup/leads/camera-wedge-2026-08-23.md`](power/bringup/leads/camera-wedge-2026-08-23.md).
Per-branch entries: the by-branch view below, 33f-3 and 33f-4.**

Measured 2026-08-23 on r73. Something in normal camera use leaves the pipeline
un-teardownable: `qcom-camss ...: VFE halt timeout`, then a
`qcom-iommu-ctx ...: timeout waiting for TLB SYNC` storm at 5 s intervals for up
to ten minutes — 60 to 125 of them — sometimes joined by an `rcu_preempt` stall,
and then `watchdog0: pretimeout event`. The debug layer's watchdog is doing
exactly what it is for; without it the phone would simply be dead.

☠️ **It fires on roughly one camera-touching run in two, and that ruins the
obvious method.** A full day of one-run-per-arm bisecting "cleared" four separate
arms — the pre-camera checks, checks 44/45, checks 40–43, and the whole camera
block on a fresh boot — and at a ~50% rate each of those clearances was a coin
flip. All four are retracted. Any future arm-by-arm comparison needs **several
runs per arm and a stated rate**, not one run and a conclusion.

What is established, because it was observed rather than inferred:

* the signature above, in four separate resets;
* `44-camera-af-windows` taking ~502 s instead of ~5 s is a **symptom** of an
  already-damaged camera and not a cause — it was read as a duration for hours;
* ☠️ **RETRACTED 2026-08-25.** This bullet used to read: *"a `cci ... timeout`
  plus `imx363 ... -110` fires at boot, ~13 s in, ... with no camera client in
  existence. That cuts against the explanation ... which blames a client
  colliding with a teardown."* It is **not a symptom at all** — it is our own
  driver working as designed. `imx363_power_on()` carries a deliberate warm-up
  loop whose comment says why: *"The very first transaction after power-up
  reliably times out on this board (slow GPIO-switched rails)"*. So probe →
  `power_on()` → the first `cci_read` times out (**the one `-110` in the log**)
  → the retry 5 ms later succeeds → `imx363_identify_module()` reads the chip id
  silently. That is exactly what the boot journal shows: **one** `imx363` line
  and **no** "failed to read chip id" beside it. Verified on r76, boot of
  2026-08-25 11:02:52. The argument this bullet made against the
  client-vs-teardown explanation therefore falls with it — that explanation is
  neither supported nor contradicted by anything here.
  ☠️ Two details of the original observation were also wrong: it fires **97 ms
  after the FIRST remoteproc (WCNSS) comes up**, not between the APR service and
  the second one — the modem's remoteproc only comes up at 16.6 s. A `dev_err`
  from a shared helper is not evidence about the caller;
* the rate, ~3 wedges in 6 independent runs.

**The current move is a hunt, not a bisect.**
`docs/power/bringup/tools/camera-wedge-hunt.sh` repeats the camera block from a
fresh reboot each pass with `kmsg-tap.sh` streaming the kernel log to the
**host**, and stops at the first fault so the onset is captured. The log has to
live on the host: the phone's rootfs is 93% full, journald therefore vacuums the
boot before last, and a reset destroys its own evidence — measured, a run that
provably reset left `journalctl -k -b -1` answering `-- No entries --`.

## ★ THE GOAL (stated 2026-08-24 evening): pmOS consumption down to the UT level or below

Set by Lajosházi, László Gergely. This is the objective the whole power track
serves; everything below is a means to it, and an item that does not move the
level is not a power item however interesting it is.

**The level to beat, measured the same evening over a 60-minute window:** UT idles at **29.7 mA** (panel
off, radio up, WiFi associated, on battery, `bms/cc_soc`), against pmOS's 58-63
mA on the same protocol. ☠️ Our best *asleep* number — the radio-low leg of the
same day — is 40.8 mA, so **the oracle awake beats our phone asleep**. The gap
is idle depth, not suspend depth.

☠️☠️ **The target number is disputed and this heading figure must not be quoted
alone.** "Panel off" in that measurement was never verified against the panel
itself — the witness used was the backlight, and the oracle's panel is fully
powered at brightness 37 with the LCDB bias rails at 5500 mV. Three readings now
exist for the same quantity: **29.7** (2026-08-24 evening), **15.3** (2026-08-24,
floor), **31.1** (2026-08-25, floor, four legs). Until one instrument takes the
oracle's panel down with the compositor's agreement — and as of 2026-08-25 there
is none — the goal is stated as a *direction*, not a threshold. See "Before
anything else: the oracle has never been measured screen-off" below.

**What this reorders.** "Reach `vlow`" was closed as a phantom earlier the same
day; "sleep deeper" is now demoted with it. The modem lead keeps its place
because it is worth ~36 mA and the mechanism is named, but it is no longer the
frame — it is one contributor to a level.

### ☠️ 2026-08-30 — what the night cost, and what it left standing

**Retracted in full:** the IPA data-path handshake lead. It works — the callback
and the INIT_DRIVER work both run, and the driver's silence is what *success*
looks like on that path. Every reading that pointed at it (an "unattended"
service 49, a mismatched instance, a dropped registration) was an artefact of
reading absence. `leads/ipa-modem-handshake.md` and `leads/vendor-kernel-sources.md`
stay for the method and the trees; the hypothesis is dead.

### ☠️☠️☠️ 2026-08-30 (08:15) — reopened: the whole residency front was measured inside a disturbance

`leads/sleep-length-is-a-state.md`. The host's USB log shows every "full" sleep
this project ever recorded equals its own alarm exactly, that the short regime is
a state which recovers when the phone is left alone, and that the disturbance is
**the act of waking** (258 → 27 → 3 s with nothing between the legs). So every
back-to-back A/B here compared two saturated arms, and "no difference" was
indistinguishable from "both arms saturated". What that costs:

- the terse result below is **not** "terse does not help" — it is "both arms were
  in the disturbed regime". To be re-run with a measured recovery gap and a 900 s
  alarm;
- the eleven dead duty candidates stay dead as *hypotheses*, but any of them
  killed by "the duty did not change" was judged inside this frame;
- the consumption model and the audio result are untouched — neither depends on a
  sleep duration.

**Settled (08:00), after two wrong answers on the way:** the suspend path is not
the variable, and neither is terse. Six legs alternating the paths with a
ModemManager restart before each slept **52 / 61 / 62 / 61 / 63 / 63 s** — terse
applied on three of them, and it changed nothing. ☠️ Both earlier readings were
the same class of instrument bug and are withdrawn: the "82/242/241/242" A-B-A-B
was reading terse carried over from the preceding leg, and the "305 s" was a
script sitting for `alarm + 5` seconds because `systemctl suspend` does not
block. From here on the sleep duration comes from the kernel's own
`PM: suspend entry/exit` pair, with the host's USB disconnect/reconnect log as an
independent witness that touches nothing on the phone. Captures:
`power/bringup/captures/2026-08-30_{susp-path-ab,terse-call}/`.

**✅ And the responsiveness half of the goal is safe:** an incoming call reaches a
sleeping, terse phone and rings, in the same second the suspend ends. So quieting
the modem is not inherently in tension with being callable — the open question is
only *what else* rings the SMD edge, since terse's 3GPP unsolicited events are
evidently not it.

Two things did fall out of that run, both smaller and both real:

- ☠️ **the modem's Linux IRQ number moved** — it is `139` on this boot and `141`
  is now `wcn36xx_tx`, the WLAN transmit interrupt. Everything written here about
  "IRQ 141, the modem's SMD edge" was true when written. Identify it by the row,
  not the number: `awk '/smd-edge/ && $(NF-2)==57' /proc/interrupts`;
- ☠️ **the run's empty `# MM inhibitor:` line was an instrument bug** — a heredoc
  ate the awk quotes on the way to the phone. The daemon holds its `delay` sleep
  inhibitor throughout, and the journal shows it notified about both logind legs
  and neither `rtcwake` one, so the A/B contrast is *better* evidenced than the
  first write-up said. **A field that reports "absent" is a claim about the
  instrument first;**
- ★★★★ **nobody asks the modem to sleep, and pmOS decided that, not us.**
  `postmarketos-base-ui-modemmanager-systemd` ships a drop-in forcing
  `--test-quick-suspend-resume`, where MM does nothing to the modem across a
  suspend. Every consumption measurement so far ran in that mode. The other
  branch, `--test-low-power-suspend-resume`, is the open lever — measured next,
  with a live incoming call during the sleep, because a radio in low power may not
  deliver one and the target is parity *at UT's responsiveness*;
- ★ **the modem interrupted one of four suspends, not four of four.** "The SMD
  edge terminates every suspend" is a *state* — the same phone slept 601 s with
  `mmcli --disable` and the daemon still running — not a permanent property. That
  makes the indication-subscription reading stronger, not weaker.

**Still standing, and unaffected by any of it:**

- the consumption model, `mA = 54.9 + 135.0 x MPSS-duty`, and what it decides;
- the audio result — the stack is not on the idle bill, three boots with the
  floor as the measure — so the audio series is free to go upstream;
- eleven dead candidates for the modem's duty, the IPA one now included;
- the band lever (~14 duty points, ≈12 mA) as a measured lead, not a knob.

☠️ **The methodological lesson of the night is worth more than the leads it
killed:** *before building on "nothing happened", find the log line a success
would print.* Four instruments in a row measured our side's intent — a source
constant, a module list, a service listing, a socket guard — and none measured
whether the thing had happened. A kprobe on the function answered it in one run.

### ★★★★★ 2026-08-29: the goal now has an arithmetic, and it says what is reachable

Fitted across the three radio-low legs, **`current [mA] = 54.9 + 135.0 x
MPSS-duty`** — one line that predicts the oracle (6.1 % → 63.1 mA against 55-64
measured) and pmOS (34.8 % → 101.9 mA against 98-101) from the same two
coefficients. The intercept is **54.9 mA** and the p10 floor reads 53-54 mA in
every leg regardless of duty.

So the goal splits cleanly, and it is worth stating in the file that holds the
goal:

| target | reachable how |
|---|---|
| **oracle parity, 55-64 mA** | **yes, and exactly by the modem term.** 34.8 % → 6.1 % of duty is 63 mA. That is the whole of this front and its ceiling |
| **≤50 mA** | **not from the modem at all** — it is below the intercept. It needs the AP to sleep, and `APSS XO off` reads 0.0 s in every window on *both* systems |

> ☠️ **2026-08-30 — scope correction on the second row, not a new number.** The
> `APSS XO off = 0.0 s` evidence was gathered on a system that **could not stay
> asleep**: 2 completed suspends in 120 attempts. So it says the AP never slept
> *in those windows*, which is true, and it does not say the AP cannot — the two
> read identically and only one of them prices the target. On this date the
> phone filled **four consecutive 600 s windows**, radio up and registered.
>
> The row is therefore **unpriced**, not disproven, and the instrument that
> prices it is free: `xo_accumulated_duration` accumulates and is readable only
> while awake, so **two snapshots around a suspend give the integral directly** —
> no sampling during the sleep, which is impossible here anyway (the battery
> attributes that look readable across a suspend are cached; that is the case
> that produced 209 mA in an awake control window reading 130). Wired into
> `power/bringup/tools/run-wake-qmi.sh`.
>
> Do not quote either reading as progress until that delta exists. The first row
> — oracle parity by the modem term — is untouched by this.

☠️ This **retracts** the same morning's "~15 mA has no owner", which mixed a
coefficient from one run with a floor from another. A model assembled out of two
runs is not a model.

**What it reorders.** The duty work is the goal; the residency work is the
responsiveness half and does not reach the number. They stay separate items and
the residency one must not be quoted as progress toward the level.

### ★★★★★ 2026-08-25: the gap is wakeups, and the two biggest wakers were OURS

Named by tracepoint, panel proven off, machine 96 % idle. Full account and the
numbers in [`power/bringup/findings-log.md`](power/bringup/findings-log.md)
("the idle gap named").

1. **`apcs_hold_cluster()` took a *global* `cpu_latency_qos`** to keep one
   cluster out of power collapse during a PLL relock. Every toggle runs
   `wake_up_all_idle_cpus()`: **45.8 pm_qos updates/s and 128 IPIs/s** on an
   idle phone — two thirds of all IPI traffic — and both clusters barred from
   power collapse for each hold. **Fixed:** the hold is now applied to the
   owning cluster's cpuidle devices, which costs no IPI (`wip/7.1.3/power`
   `68dcadbd`, on `integration` and `debug-int`, shipped as r76).
2. **A diagnostic harness left running since August.** `spkwatch` alone had
   burned **365.75 s of CPU over 14 024 s of uptime = 2.6 % of a core,
   permanently**, forking four processes and doing an i2c transfer every
   second. Disabled with `ringwatch`, `fp3-powerlog`, and `avahi`/`cups`
   (which the oracle does not run either, so they were also an unfairness in
   the matched pair). Effect before any kernel change: `sched_wakeup`
   **1951 → 1172 / 10 s**, `cpu_frequency` **916 → 440 / 10 s**.

☠️ **Neither would have been found by looking harder at Qualcomm's code.**
Before hunting a platform for a power gap, subtract what the port itself is
doing to it.

**Ruled out here, do not re-chase:** the display (CRTC off, DSI suspended, zero
MDSS interrupts — the earlier `msm_mdss 79/s` lead was sampled with the screen
ON and is withdrawn); schedutil rate limiting (limit ~10 ms, allows 100/s, we
measured 22.9/s — the transitions are real demand); sleep inhibitors (all
`delay` mode); journald (journal does not grow at idle); and the RPM sleep-set
layer, which is already on the running kernel and cannot save anything in its
`on-in-suspend`/`both_sets` form.

**Measured on r76 (the aggregate, one idle-ab hour, same protocol):** median
**148–157 → 98.3 mA (−35 %)**, floor unchanged (53.9/54.3 → 52.9) — the shape
both fixes predicted, since neither touches a continuous draw. Burstiness
(median ÷ floor) went **2.75× → 1.86×** against the oracle's **1.97×**: pmOS now
bursts *less* than UT. **The wakeup half of the gap is closed.**

### What is left: continuous draw — and as of 2026-08-25 afternoon, an oracle number we can no longer trust

The census against slot a was run and **all three questions were answered**.
Two of them are closed, the one ranked last produced the only lead, and the
comparison's own premise came apart in the process. Full record:
[`power/bringup/findings-log.md`](power/bringup/findings-log.md), captures
`2026-08-25_ut-*`.

1. ✅ **The modem does not move the oracle's floor.** Four 30-minute legs —
   both modems on, both `Powered=0`, both back as a control, and one with the
   phone untouched — gave **30.8 / 31.1 / 31.1 / 31.1 mA**. A modem registered
   on LTE contributes nothing continuous. ☠️ There are **two** modems
   (`/ril_0`, `/ril_1`); disabling only the first leaves the second powered.
2. ✅ **The debug UART is not the difference.** The oracle runs the same
   `gcc_blsp1_uart1_apps_clk` at the same 3 686 400 Hz with `console=ttyMSM0`
   *and* `earlycon=` on its cmdline. Its clock census is **43 enabled against
   our 37** — the oracle runs *more* clocks, not fewer.
3. ✅ **The rail diff is closed with NO difference.** ☠️☠️ It was published as
   a lead for a few hours — `s3` and `s4` enabled on ours with the panel dark —
   and the matched capture killed it: `regulator_summary` is a **tree**, and
   the indented rows under a rail are its **child regulators**, not only its
   consumers. Both of `s3`'s direct consumers (`camss-vdda`, `dsi-vdda`) read
   **0**; `s3` is up because its child `l3` is, and `l3` is held by the USB
   PHY. `s4` is up because its children `l5` (eMMC I/O) and `l7` (USB PHY PLL)
   are. Our `s3` sits at its declared **minimum** 984 mV where the oracle
   raises it to 1225 for its display. Leaf for leaf the two rail sets match;
   the only extra rails are the oracle's LCDB display-bias pair at 5500 mV,
   which **it** keeps up and we do not.

### ☠️☠️ Before anything else: the oracle has never been measured screen-off

Its panel **never blanks on its own** — `powerd`'s inactivity action is not
`display-off` and it holds **no inhibitor** while staying lit. `Unity.Screen`'s
`setScreenPowerMode("off")` returns **`true`** for two reason codes with the
panel still powered. Writing `4 > /sys/class/graphics/fb0/blank` drops the MDSS
clocks but is only half a blank: the PMI632 **LCDB bias rails stay at 5500 mV**
(`lcdb_ldo`, `lcdb_ncp`) and the compositor undoes the write within minutes.
☠️☠️ [`power/bringup/tools/press-power-key.py`](power/bringup/tools/press-power-key.py)
(uinput `KEY_POWER`) was written to produce a real screen-off and instead
**switched the phone off** — found on the offline-charging screen, recovered
only by a held hardware button. Its likely mechanism is a release that was
never seen; the fix in the file is a hypothesis and is **not validated**. Do
not run it unattended. There is therefore currently **no instrument** that
takes the oracle's panel down with the compositor's agreement.

So **every UT idle figure quoted in this file, the 15.3 mA floor included, was
taken in a state the phone is not in when its screen is off**, and the "3.5×
floor" framing rests on that number. Two facts are waiting on it: today's
oracle floor measured **31.1 mA** across four legs (minimum sample 30.2 against
yesterday's 14.3), and the LCDB bias rails are the obvious suspect — which will
not be named as the cause until they are measured off.

### ☠️ Where the hunt actually stands: no candidate, and a target number that disagrees with itself

Everything the census was meant to find is excluded. **Seven exclusions, zero
findings: ~38 mA of continuous draw remains with no hypothesis attached.** The
three above came from the oracle census; these four came from our own side the
same day, and they are listed here so the count is not read as four:

4. ✅ **Userspace is not it.** A headless leg (`postmarketOS-headless`,
   `systemd.unit=multi-user.target` — no compositor, no session, no GUI at all)
   floored at **52.9 mA**, against **52.9** with the full desktop running.
   Identical to the tenth of a milliamp. The entire graphical stack is worth
   nothing on this phone, which is also why `slope-leg.sh` no longer stops
   `greetd` — the measurement does not need the phone to stop being a phone.
5. ✅ **The CPUs are not it.** All eight cores sit at ~99 % residency in
   `cpu-power-collapse` over a 60 s differential of
   `cpuidle/state*/{time,usage}`. There is no core left awake to find.
6. ✅ **Nothing is blocking suspend.** No entry in
   `/sys/kernel/debug/wakeup_sources` carries a nonzero `prevent_suspend_time`.
7. ✅ **The ADSP is not it, and stopping it *costs*.** A/B/A′ =
   **52.9 / 56.3 / 54.6 mA** — the leg with the ADSP stopped is the *worst* of
   the three. So `lpass-never-sleeps` is a true observation worth no
   milliamps, and it is now closed as a power item.

☠️ Note what these seven have in common: **every one of them counts events.**
Interrupts, wakeups, clock enables, rail votes, residencies, service cuts. A
continuous draw that no event-counting instrument can see is the one thing this
whole battery of instruments is structurally unable to find, which is why item 2
of "Next, in order" below is not "another census".

Worse, the number the goal is measured against is unresolved: the oracle's
floor came out **31.1 mA** today across four legs (minimum sample 30.2) against
**15.3 mA** on 2026-08-24 (minimum 14.3). Until that factor of two is
explained, "pmOS idles at 3.5× the oracle" is not a measurement — it is two
measurements that disagree.

**Next, in order:**

1. **Settle the oracle's own floor.** Repeat the 2026-08-24 leg exactly —
   same window, same untouched phone, and a battery in the same state (that
   leg started at 4.05 V and ~76 %, today's at 4.35 V off a full charge). If it
   reproduces at 15 mA, find what today's four legs had that it did not; if it
   comes back at 31, the 3.5× framing goes and the goal is restated.
2. Only then a new hypothesis for the continuous draw — and it will have to
   come from an instrument that measures *level*, not events, because every
   event-counting instrument has now been run.

#### ✅ CLOSED 2026-08-27 — item 1: both ladders ran, and the premise was the thing that was wrong

> **Read the closing block at the end of this item first.** Everything between
> here and it is the reasoning as it stood while the question was open, kept
> because the wrong turns in it are the point.

#### the state as it stood 2026-08-26 — worse than a factor of two

The oracle was re-measured with the panel **provably** off (`lcdb_ldo`/`lcdb_ncp`
`state` = `disabled` carried in every sample, not just checked at the door). It
is not two readings that disagree, it is **three**, and they span 4.5×:

| run | start V | start `cc_soc` | floor (p10) | integrated |
|---|---|---|---|---|
| 2026-08-24 | 4.050 V | ≈76 % | **15.3 mA** | 32.2 mA |
| 2026-08-25 | 4.276 V | ≈98 % | 31.1 mA | 54.6 mA |
| 2026-08-26 w1 | 4.315 V | ≈99 % | 69.9 mA | 61.0 mA |
| 2026-08-26 w2 | 4.282 V | ≈95 % | 71.6 mA | 64.3 mA |

★ **Boot recency is excluded** — w1 and w2 are the same boot at uptime 3 min and
66 min and agree to 1.5 mA. ★ **pmOS does not do this**: 53.9 / 54.3 / 52.9 mA
across three captures at 4.224 / 4.170 / 4.294 V, a 1.4 mA spread.

So the surviving candidate is **state of charge** — and it is *unproven*, because
all four windows above that read high sit in a narrow 92–99 % band and the only
low one is on a different day. `tools/soc-ladder.sh` is walking the pack down on
one boot, eight 1-hour windows, to turn the across-days correlation into a curve
or kill it.

☠️ **The ladder cannot decide real draw versus gauge artifact.** There is no
second instrument on the oracle: `current_now` and `cc_soc` are both the PMI632
QG block behind one current-sense front end. (This was published as
independent confirmation and withdrawn within the hour — see findings-log.)

**After the ladder, whichever way it goes:** run the same ladder on **pmOS over
the same SoC band**. Same pack, same PMIC, but our own mainline gauge rather than
the downstream QG algorithm — so a *hardware* nonlinearity in the shunt/ADC
appears on both sides while a *downstream-software* artifact appears only on UT.
It is a partial discrimination, and it is the best available without an external
power meter, which needs a human at the phone.

☠️ And note what this does to the goal's arithmetic either way: the pmOS number
is stable and the oracle's is not, so **"pmOS idles at N× the oracle" has no
single value** until the oracle's dependence is characterised. The comparison has
to be made at a *matched* state of charge, which no published pair so far was.

#### ✅ THE ANSWER, 2026-08-26/27 — both ladders, and the 4.5× was an outlier

Eight rungs on the oracle (14:07-22:10) and eight on pmOS (23:10-07:13), the pack
charged back to the oracle's rung-1 mark **on the UT side** before the slot
switch so pmOS booted onto a pack already there.

**State of charge is dead as an explanation, in both its versions.** Over
94 % -> 69 % and 4.262 -> 3.967 V the oracle's floor does not move (69.0-76.6 mA,
no monotonic trend) and its integrated draw does not either (58.9-64.3 mA) — a
spread narrower than one window's own noise. ☠️ And the threshold version dies on
**rung 5**, which spans 4.068 -> 4.050 V, exactly the 2026-08-24 capture's
voltage, and reads **71.0 mA floor / 63.1 mA integrated** against that capture's
15.3 / 32.2. Same phone, same pack voltage, same instrument, 4.6× apart.

So **the 15.3 mA row above is withdrawn**, and with it the "3.5× against us"
framing. The reproducible oracle figure, over ten consecutive hours, is
**69-77 mA floor / 59-64 mA integrated**.

**The matched comparison, which is what item 1 existed to make possible:**

| over 8 h | UT | pmOS | pmOS vs UT |
|---|---|---|---|
| **energy (I·V)** | **525.6 mW** | **593.5 mW** | **+12.9 %** |
| current (integrated) | 129.0 mA | 154.1 mA | +19.5 % |
| floor (p10) | 72.2 mA | **56.9 mA** | **−21 %** |
| median | 126.3 mA | 161.8 mA | +28 % |

Our floor is *below* the oracle's; our median is above it. The night costs 12.9 %
more energy, and the deficit is **burst behaviour, not continuous draw**.

☠️ **Compare energy, not mA** — the ladders covered different parts of the pack
(pmOS 4.150 -> 3.708 V), and 6.6 of those 19.5 points were the discharge curve.

#### ⏳ OPEN — the goal, stated by the operator 2026-08-27: usable behaviour AND good battery

The target in the operator's words: **an incoming call must not wait more than
1 second, and the phone should still idle well.** That is a product requirement,
not a measurement, and it decides the call-wake ↔ deep-sleep trade that has been
sitting on the "waiting on a human" list since 2026-08-23.

☠️ **First, what this is NOT.** The eight-hour ladders measured the phone
**awake** — `idle-ab.sh` is an awake-idle instrument and pmOS never suspended
during those eight hours, because automatic sleep is off. So the ladder's "+28 %
median" is awake burstiness (timers, daemons, IPIs), **not** wakeups out of
suspend. Two separate axes, and only one of them was measured:

| axis | where it stands | what is reachable |
|---|---|---|
| awake, idle, panel off | floor 56.9 mA, median 161.8 mA (2026-08-27 ladder) | trimming the bursts |
| asleep (s2idle) | **switched off on purpose** | 43.3 mA, measured 2026-08-19 with the modem stack cut |

☠️ **And the power-saving setting is not the knob it looks like.** phosh's
`sleep-inactive-battery-type` is `'nothing'` — a decision, not an unexamined
default. Turning it on does not give a quieter phone today: the modem's SMD edge
(IRQ 141) **terminates every suspend**, 4 of 4, after 5 / 9 / 62 / 5 s out of 600
asked. The aggressiveness is not mis-set; the suspend itself fails.

**What is already solved:** call-wake works. r66 arms every rpmsg edge and a live
call raised the phone 15 s into a 300 s suspend window. The 1-second requirement
does not depend on that path.

**What is already excluded:** the ring is not ours. With `ModemManager` and
`rmtfs` both stopped the modem-edge poke rate stayed inside the baseline spread
(+24 / +33 / +20 / +31 across four legs), so no AP-side userspace policy quiets
it, and arming the edge only relabels the aborts rather than stopping them.

**The next measurement, and it is specific:** capture the rpmsg channel and
payload of the message that arrives immediately after `PM: suspend-to-idle`. The
wake now has a timestamp, an IRQ (141 = `hwirq 57` = `GIC_SPI 25` =
`remoteproc@4080000/smd-edge`) and a driver to trace from. If the traffic is
routine flow-control or a keepalive, the fix is AP-side and `qcom_smd` is
upstream, so it would be an upstreamable one; if it is real data, the fix is
modem configuration (PSM / eDRX / paging).

**Then, and only then, the trade can be designed rather than guessed:** an
inhibitor held while ringing, or arming the edge conditionally (screen off, no
long sleep wanted), with the 1-second call latency as the acceptance test.

Second front, independent of the modem and available now: **the awake burstiness
itself**. Our floor is 21 % below the oracle's and our median 28 % above it, so
whatever wakes the phone while it is awake is worth more than it looks. The two
biggest such wakers found so far were both ours (`apcs_hold_cluster()`'s global
`cpu_latency_qos`, and a `spkwatch` harness left running since August). Nothing
says there is not a third.

##### ⏳ OPEN — front two, 2026-08-27: the burst is not code and not the CPU

Opened and immediately narrowed, by two instruments that share no mechanism (this
matters: the standing lesson here is that two witnesses on one layer are one
witness read twice). Both on a proven-dark panel with the charge input cut.

1. **The trace says no.** `burst-source.sh`, 24 321 `workqueue_execute_start` +
   `timer_expire_entry` events against 71 current samples on one clock. Split each
   event into the 5 s bin ending at a current sample, then split those bins by
   whether the sample was a burst: **313 events per burst bin against 316 per
   quiet bin**, every top function at the same per-bin rate, the 1 % difference
   pointing the wrong way. ☠️ `psi_avgs_work` is 4 897 of ~9 000 workqueue
   executions and looks exactly like the answer — it is flat from end to end.
   **Rank a trace and you describe the background; split it by the thing you are
   explaining and you test it.**
2. **The machine says no.** `burst-attrib.sh`, no tracepoints at all, 180 samples,
   current 53 → 473 mA (**9×**): `busy_pct` 1 vs 1, power-collapse residency
   **99 vs 100 %**, wakes 77/s vs 77/s, both cpufreq policies pinned identically,
   wlan 2 vs 2 pps. **The cores are collapsed 99 % of the time during the burst.**
   The old census line "the CPUs are not it" was about the floor; they are not the
   burst either.

##### ★★★★ 2026-08-27 evening — the burst has an owner: the MPSS core

`burst-master.sh` asks the RPM what each master did, per sample. Its own
burst/quiet split answered "not me" for the sixth time — **and the answer was in
the same file.** A master that is up a third of the time has a median of zero on
*both* sides of a split by current. Split by the candidate **cause** instead:

| | window 1 | window 2 |
|---|---|---|
| MPSS core up | 33 % of samples | 37 % |
| median, MPSS up | 166 mA | 158 mA |
| median, MPSS down | 74 mA | 67 mA |
| **difference** | **+92 mA** | **+91 mA** |

with both MPSS and PRONTO down the floor is **63 mA**, PRONTO alone ≈ +45 mA, and
the two are not the same variable (they agree on 107 of 189 samples). **Split by
the effect to test a story; split by the cause to find one.** Both directions are
needed and this investigation had only ever used the first.

##### ★★★★ 2026-08-27 — the two systems do not run the same modem firmware

Read off the device, not guessed:

| where | modem build |
|---|---|
| `modem_a` **and** `modem_b` partitions (`verinfo/ver_info.txt`) | `MPSS.TA.3.1.c1-00026-8953_GEN_PACK-1.**325768**.1.329896.1` |
| `/lib/firmware/qcom/msm8953/fairphone/fp3/modem.mbn` (what pmOS loads) | `MPSS.TA.3.1.c1-00026-8953_GEN_PACK-1.**356774**.1.**425464**.1` |

Both slots' vendor firmware sets are the 2021-10-25 `SDM632.LA.2.1-00015` metabuild
(`Meta_Build_ID` identical on a and b), and every other piece the phone runs — RPM,
TZ, the bootloader — comes from those partitions on **both** systems. Only the
modem image is different, and it is different because pmOS loads its own copy from
the rootfs.

**This is both a confound and a candidate.** A confound, because the oracle's MPSS
duty (6.3 %) and ours (34–36 %) were measured on *different modem builds*, and that
must be said wherever those two numbers appear together. A candidate, because a
modem image paired with an RPM and TZ it was not built against is exactly the kind
of thing that changes sleep negotiation, and it is the only difference left after
every Linux-side lever came back flat.

**The experiment, not yet run** (it needs a firmware file swap and a reboot, so it
is the user's call):

```sh
F=/lib/firmware/qcom/msm8953/fairphone/fp3
mount -o ro /dev/disk/by-partlabel/modem_b /tmp/m
cp -a $F/modem.mbn $F/modem.mbn.425464bak          # rollback is this file
cp /tmp/m/image/modem.b* $F/                        # 45 MB, split image
cp /tmp/m/image/modem.mdt $F/modem.mbn              # the DT names modem.mbn;
                                                    # qcom_mdt_load reads the
                                                    # metadata here and pulls
                                                    # modem.bNN beside it
umount /tmp/m && reboot
```

then `mmcli -m 0` must reach `registered`, and `burst-master.sh 360` gives the
MPSS duty to compare against the 34–36 % measured on 425464. **Rollback is
restoring `modem.mbn` from the `.bak` and deleting the `modem.b*` files.** ☠️ Check
`mba.mbn` too: the partition's is byte-for-byte the same size as ours, and MBA is
what authenticates the modem image — if the swap fails to boot the modem, that
pairing is the first thing to look at.

☠️ Do not run this while a measurement is in flight, and record `capacity` and
`voltage_now` before the reboot: it is a new boot, so it is a new baseline.

**Next, in order:**

1. ⏳ **the intervention** — `burst-master-knob.sh modem …`, A-B-A′ on
   `mmcli --disable` where what is compared is **MPSS's duty cycle**, not the
   current. The earlier current-only A-B-A′ was flat (2 mA against a 3 mA
   spread) and that told us nothing about whether the MSS core kept waking.
   ☠️ Never through `/sys/class/remoteproc`.
2. ⏳ **LPASS never releases the crystal** — `XO total duration` 9.4 s against
   5½ hours of uptime, `LPASS_xopct` = 0 in all 189 samples of both windows. It
   is constant, so it cannot be the burst; it is the right shape for the standing
   `vlow = 0` item and it belongs to the **floor**. First suspect is a userspace
   sensor consumer holding the ADSP up (`iio-sensor-proxy` for phosh's
   auto-rotate); test it as a knob run and read `LPASS_xopct`, not the current.
3. ⏳ **what wakes MPSS 35 % of the time**, given that disabling the RF does not
   stop it. It is the same subsystem whose SMD edge terminates every suspend
   (IRQ 141), so the awake front and the suspend front now have one suspect
   between them.
4. ⏳ *(superseded, kept for the trail)* **`burst-modem-ab.sh`** — A-B-A' on the RF with `mmcli --disable`, never the
   remoteproc (restarting that costs audio until reboot and a mixer write
   afterwards oopses the kernel). The modem is the last thing on this phone that
   can spend hundreds of mA without waking a CPU, and it is independently the
   thing that terminates every suspend (IRQ 141, the SMD edge).
2. If the modem is flat too, **a rail census timed to the burst** — not another
   profiler. Every profiling instrument available has now been run and all of them
   agree the power is not a running instruction.
3. Still unattached to any of this: the **~81 s pmOS-only period**. Close the
   `wifi: ?` blind spot in `idle-ab.sh` first — the most obvious periodic-task
   suspect is the one field the instrument leaves blank.

#### ⏳ OPEN, and it is now the highest-value instrument work here — a coulomb counter on mainline

The oracle exports `cc_soc` + `full_uAh=3060000`; mainline exports no `cc_soc`
and `full_uAh=?`. On the oracle, where both exist, integrated `current_now` and
the coulomb counter disagree by **2.056×** over the same eight hours (1030.6 vs
501.2 mAh) — and in the direction that rules out sampling shortfall, because too
few samples under-count. The likeliest reading is that **the sampling itself
wakes the phone**: a sysfs read every ~5 s brings it up, so `current_now` measures
the awake-and-idle draw while the counter integrates in hardware, sleep included.

Consequences, both live:

* ☠️ **That ratio must not be carried to pmOS to "correct" its numbers.** It is a
  property of how often a system wakes, which is the quantity under comparison.
  Every figure in the table above is integrated-against-integrated.
* **Our absolute draw is known only through an estimator the oracle proves can be
  2× off.** The comparison survives because both sides are read the same wrong
  way; nothing else does. Whether the PMI632 QG block can expose a raw count to
  mainline — and what it would take in `qcom_smbx`/the QG driver — is unanswered.

#### ☠️☠️ OPEN — OUR GAUGE IS ~30 POINTS OPTIMISTIC, and as of 2026-08-28 the CAUSE IS MEASURED

**`charge_full` is the 3 060 000 µAh nameplate; the pack holds 2185 mAh.** One
17.94 h discharge from a terminated charge to power-off (`captures/2026-08-28_discharge-to-shutdown/`)
integrated 2185 mAh while the gauge fell only 100 → **35 %**, ending at
**2.864 V**. 2185/3060 = 71.4 % of nameplate spent, so a coulomb counter scaled to
the nameplate lands near 29 % — which is where it stopped. The missing points are
not drift: they are the difference between the nameplate and the cell.

**The fix is `charge_full`, learned rather than declared.** The QG path already
tracks a full-to-empty excursion; nothing else in the mapping needs to change for
the user-visible number to become honest.

☠️ Also measured, and its own item: the phone crossed `voltage_min_design`
(3.400 V) with the gauge reading **39 %** and kept running for **45 minutes**
down to 2.864 V. Nothing in the stack acts on that property — the shutdown when
it came was the hardware's, not a managed low-battery cut-off. A phone that
ignores its own design minimum will keep taking the cell deeper than it should on
every flat-battery event.

<details><summary>The 2026-08-27 crosscheck that opened this, kept for the trail</summary>

##### ☠️☠️ OPEN, and it outranks the idle work — OUR GAUGE IS ~30 POINTS OPTIMISTIC

Measured 2026-08-27, the direct way: the pack was walked down to the **bottom of
the pmOS ladder** (63 %), rested 300 s with the charge input open, read, then the
slot was switched and the same pack read on the oracle.

| | reading |
|---|---|
| pmOS, 09:22:51 | **cap=63 %**, ocv **3.735 V**, `charge_now/charge_full` 63.1 % |
| UT, 09:27 / 09:29 / 09:30 | **cap=33 / 34 / 34 %**, `cc_soc` 3389 → 3434 |

☠️ The oracle's two numbers are **not** independent — `capacity` and `cc_soc` are
one QG block behind one front end. The independent handle is the **OCV**: 3.735 V
after 300 s of rest is roughly the 25-35 % region on this chemistry, where 63 %
would want 3.85-3.90 V. That points at ours being wrong, and "points at" is the
right strength — this pack's OCV→SoC curve has never been characterised.

**Why this outranks the idle current:** if the phone says 63 % while the pack
holds ~33 %, it tells its owner it has twice the battery it has, right up until it
dies. Four gauge faults were already fixed in `qcom_smbx`/the QG path in August;
this is a fifth, and it is the user-visible one.

**What it invalidates:** the `capacity` row of the ladder comparison (94→69 vs
92→63 "so pmOS is 14 % worse") and the runtime estimate derived from it. **Not**
the energy figure — 525.6 vs 593.5 mW comes from `current_now`/`voltage_now`, and
the voltage travel already agreed (442 mV against 295).

**What decides it, and nothing short of it will:** one full instrumented discharge
on pmOS from a known-full pack to shutdown, `current_now` integrated across the
whole run against what `capacity` claims at each point. It also yields the OCV→SoC
curve this pack has never had. ☠️ Needs the ladder harness's capacity floor
**disabled deliberately** for that one run, and someone aware the phone will end
it switched off.

Capture: `power/bringup/captures/2026-08-27_gauge-crosscheck.txt`.

</details>

### ✅ RAN, and it answered a different question than it asked — 2026-08-26

The A-B-A completed (3 jobs, rc=0, guardian silent), and what it produced was not
a current comparison at all. Full account: findings-log 2026-08-26 entries.

**What it found.** The legs differ *categorically* in whether the phone stays
asleep, not in how much it draws while asleep:

| leg | modem | slept, of 4 × 600 s asked |
|---|---|---|
| A | up, registered | 50 + 89 + 32 + 59 = **230 s (9.6 %)** |
| B | stack cut | 2407 s (100 %) |
| A′ | ☠️ **still cut — not a control** | 2407 s (100 %) |

A follow-up `wakeup-census` reproduced it (67 s of 600 up, 601 s cut) and added
the modem side: **MPSS +179 XO shutdowns in 67 s**, crystal off 52 % of the
window.

☠️☠️ **But it is NOT a law, and I published it as one.** An instrumented suspend
an hour later — modem up, registered on LTE, same kernel, cable in — **slept the
full 601 s.** So: real, large, never seen with the modem cut (0 of 6), not the
wake-armed edge (all edges read `disabled`), and **not universal** (1 of 6
radio-up suspends ran full term). The claim is withdrawn from STATUS and the
findings log.

☠️ **Two casualties of the run itself.** Leg A's fitted 52.0 mA fails its own r²
gate (0.74, window 6× too short *because* it did not sleep) and must not be
quoted. And A′ was not a control: `restore()` restarted the services but not the
modem — a failure this project had documented on 2026-08-21 and never put into a
tool. Three tools are now fixed to verify and abort.

**Next, and it is a rate, not another story:** n identical suspends with the
modem up, one candidate variable at a time — time since boot (the aborting arms
were ~11 min in, the full-term one ~27), time since registration, battery vs
cable. Running as `srate.sh 8 600`.

☠️☠️ **A re-opening of exclusion 6 stood here for an hour and was my own column
misread.** `prevent_suspend_time` is field **10** of
`/sys/kernel/debug/wakeup_sources`; my probe tested field 9, `last_change`, which
is a millisecond timestamp and nonzero for anything that has ever fired. The
original capture reads 0 in the real column for every source. **Exclusion 6
stands and the seven are seven.** Third column-misread of the same session — see
findings-log 2026-08-26 for the rule that replaced it.

<details><summary>The original plan, kept for the protocol</summary>

### The A-B-A on r76, as designed

Started 19:31, `night-20260825-aba`, preflight PASSED, ~6 h. Three legs on ONE
descent, `SLOPE_SLEEP=600 SLOPE_CYCLES=4 SLOPE_SETTLE=600`, recharging to 90 %
between them:

| leg | what | why |
|---|---|---|
| **A** | r76 sleeping baseline, radio up, nothing cut | the sleeping numbers above are all r73-era; this is the first on r76 |
| **B** | the same with `ModemManager rmtfs tqftpserv` cut | the modem lead — the only thing that has ever moved the sleeping number |
| **A′** | identical to A | the control |

☠️ **A′ is not optional.** 2026-08-25 produced *two* results that were pure
drift and would have been published as effects without a control. ☠️ Compare
phase-A **slopes** between the legs; the derived mA is for scale only. ☠️ Leg B
leaves the phone unable to receive calls for ~100 minutes. ☠️ `systemctl stop
rmtfs` powers the modem down and a restart does not bring it back — see the
traps at the end of the modem-lead section.

Jobs file: [`power/bringup/night/jobs-2026-08-25.txt`](power/bringup/night/jobs-2026-08-25.txt).

</details>

☠️ **Do not poll the phone during a leg.** Measured 2026-08-25: 74 ssh logins
in 70 minutes — waiter loops — cost **18.3 mA** on the coulomb integral and
produced a clean monotonic trend that read exactly like a modem effect. Start
the leg with `systemd-run` and then do not touch the device until the window
has elapsed. This is the same lesson as the `spkwatch` diagnostic, arriving
from the host side.

☠️ **Instrument note that makes this cheap on the UT side, and a trap on both.**
`bms/cc_soc` is a real coulomb counter (validated both directions 2026-08-24);
`bms/charge_counter` is **not** — it did not move at all over 453 s at ~103 mA
and steps in exactly 1 % of `charge_full`, the same OCV-lookup trap as pmOS's
`charge_now`. Never price anything with `charge_counter` on either system.

## The modem lead — the only thing that has ever moved the sleeping number

> **Update 2026-08-29 — this section's frame is from 2026-08-24/25 and two things
> in it have since been superseded.** (1) The lead is no longer "the sleeping
> number": the goal's arithmetic above prices it awake, as the whole 34.8 % → 6.1 %
> duty term, and asleep it is a separate question. (2) Elimination has run out —
> nine candidates tested and dead, including every userspace daemon on *both*
> sides, a live PDP context on ours, and our client masked from boot. The two
> things that did move it are the RAT (LTE vs 2G) and the **band the network hands
> out** (~14 duty points, ≈12 mA, forced in both orders inside single boots), and
> neither is shippable as it stands. The running account is
> [`power/bringup/findings-log.md`](power/bringup/findings-log.md) and
> [`../docs/STATUS.md`](STATUS.md); read those first and this section for the
> history of how the candidates died.
>
> ☠️ **And a rule this section predates:** on this phone the modem's duty has a
> per-boot offset big enough to swallow any effect under ~15 points, so a leg
> compared against "the baseline" is worthless. Only A-B-A′ *inside one boot*
> counts.

> The "deep sleep / reach `vlow`" item this section grew out of is **closed** and
> lives in [`TODO-DONE.md`](TODO-DONE.md): a raw mmap read of the RPM's own
> records shows `vlow` count = 0 **on the working UT oracle too**, so the mode
> never occurs on this platform under any OS. There was nothing to fix and the
> planned `smd-rpm.c` handshake work is cancelled. Kept as a pointer only —
> nothing below depends on it.

The one thing that ever moved the sleeping number: **modem processor off is
worth ~36 mA** (79.1 → 43.3 mA asleep) — but every 2026-08-20/21 "service cut"
leg is contaminated by `rmtfs -P` (stopping rmtfs POWERS THE MODEM DOWN and it
stays down), so the only named mechanism is "modem off", unusable as a fix.
The lead, in order:

1. ✅ **MPSS XO-duty differential across genuine s2idle, modem normal vs
   `mmcli --set-power-state-low`** — DONE 2026-08-24 (cable-in, ~10 min,
   `captures/2026-08-24_modem-xo-duty.txt`): radio up = every suspend aborts
   early (11 s / 47 s of a requested 90) with the MPSS chopping the crystal
   ~2.5 transitions/s; radio low = full-term suspends with MPSS XO off
   essentially the whole window. So the mechanism IS RF/registration activity
   and the fix direction is modem power-save config, not host services.
2. ✅ **(a) radio-low night slope leg — DONE 2026-08-24 evening**
   (`radiolow-20260824`, cable out, 6/6 full-term suspends, rc=0):
   **phase-A −18.68 mV/h (r²=0.987) ⇒ 40.8 mA asleep**, against
   `baseline-20260819` −35.77 mV/h / 79.1 mA and `nomodem-20260819`
   −22.62 mV/h / 43.3 mA. **So radio-low buys the WHOLE ~36 mA that powering
   the modem processor off buys, with the modem still loaded.** ☠️ Read the
   2.5 mA it sits under the modem-off leg as "indistinguishable", not
   "better" — different legs, different days, run-to-run scatter at this
   resolution uncharacterised. Capture:
   `captures/2026-08-24_radiolow-slope-leg.txt`; account: findings-log
   2026-08-24 evening entry.
   (b) A true modem-off leg via remoteproc stop is now **optional** — it would
   only re-measure a number radio-low has already reached; spend the night on
   (3) instead.
3. Only then the mechanism question — what the modem does with the radio up
   that costs ~36 mA (QMI traffic? paging config? `qcom_rpm_master_stats` MPSS
   XO duration across the sleeping leg is the readout).

☠️ Traps carried over: `systemctl stop rmtfs` = modem shutdown (`-P`); a
service "restart" does NOT bring the modem back (needs remoteproc `start`,
then pd-mapper may stay broken until reboot); per-suspend voltage slopes
scatter ±87 mV/h — only whole-leg fitted slopes resolve effects this size.


## ✅ CLOSED 2026-08-30 — the modem edge IS armed at boot

> ☠️ **Read this before the section below, which is the state as of 2026-08-25
> and is now false in its load-bearing sentence.** The gap it describes — "the
> arm knob defaults to `disabled` on every boot and nothing arms it" — has since
> been filled: `userspace-power/fp3-modem-wake-arm.service` exists, and
> `tests/checks/58-call-wake-test.sh` fails when it is missing or not enabled,
> so the regression is guarded rather than remembered.
>
> The running phone is armed, proved two ways on 2026-08-30 and neither by
> reading the knob: an incoming call woke it out of a 280 s sleep at 10:39, and
> every suspend that morning reported `pm_wakeup_irq` = the modem edge — a line
> `irq_pm_handle_wakeup()` emits only for a **wake-armed** IRQ, so its presence
> is itself the proof.
>
> The conclusion drawn from the old text is therefore also void: **automatic
> sleep no longer has to stay off** on this account. Whatever else gates it, it
> is not this.
>
> Kept rather than deleted because the constraint it states — idle low *and*
> calls still arriving — is the one the goal is defined by, and the paragraph
> below is where its reasoning is written down.

### (superseded) The modem edge is not armed at boot, so automatic sleep must stay off

**The wake fix itself is done, shipped and call-proven — it has moved to
[`TODO-DONE.md`](TODO-DONE.md)** ("An incoming call cannot wake the phone from
s2idle", r66/r70, with the 2026-08-25 end-to-end ring proof folded in). What is
left is one gap, and it is the reason this is still an open item rather than a
struck-through heading:

**The arm knob defaults to `disabled` on every boot, by design.**

```
.../4080000.remoteproc/remoteproc/remoteproc0/remoteproc0:smd-edge/power/wakeup
```

Every measurement that has ever shown a call waking the phone armed it **by
hand** first, the 2026-08-25 ring-through included. Nothing arms it at boot, so
on a freshly booted phone the behaviour is still the 2026-08-14 one: the call
reaches the modem and the application processor never wakes.

☠️ **Therefore automatic sleep must not be switched back on until this exists.**
The correctness constraint of the goal ("idle low, but calls still arrive") is
proven *reachable*, not *default*. A udev rule or a systemd oneshot is the
obvious shape; ☠️ it must address the remoteproc by platform address or `name`,
never by index — the numbering moves between boots (the ADSP was `remoteproc1`
on one boot and `remoteproc2` on the next), so an index-based rule will
sometimes arm the wrong co-processor and look like it worked.

The second layer that used to be listed here — something must hold suspend off
while the dialer rings — **is answered by observation** and needs no work: on
2026-08-25 the phone rang for 61 seconds without re-suspending. Identify what
holds it if you touch this area, but do not build one.
## A modem restart costs audio until reboot, and a mixer write then oopses the kernel

Found 2026-08-23 on r70 while testing the armed wake edges; full measurement in
[`power/bringup/findings-log.md`](power/bringup/findings-log.md). Three
separable defects, deepest last:

| # | defect | shape of the fix |
|---|---|---|
| 1 | `slim_rx_mux_put()` dereferences a list head that was never initialised — `list_del_init(&wcd->rx_chs[port_id].list)` on memory that only ever saw a `memcpy`. A single `amixer` write to `SLIM RX0 Mux` is enough to NULL-deref the kernel from userspace. | `INIT_LIST_HEAD()` beside the `memcpy` in `wcd9335_codec_probe()` — small, upstream-shaped, **audio** category |
| 2 | `pdata->slim_port_setup` in the machine driver latches `true` for the life of the card, but it guards state that lives in the **codec** and is wiped when the codec re-probes. `snd_soc_dai_set_channel_map()` is then never called again. | clear it on codec re-probe, or drop the latch and let the idempotent `set_channel_map` run on every `dai_init`. Inherited from `sdm845.c`, so upstream has the same hole |
| 3 | the WCD9335 does not survive a SLIMbus SSR at all: `qcom,slim-ngd-ctrl: HW wakeup attempt during SSR`, then `WCD9335 CODEC version detection fail!` and `Failed to bringup WCD9335` (85 lines). This is the functional root cause and the only one that costs audio. | **diagnosed and fixed 2026-08-23** — see the section below |

The measured chain, from one boot's journal:

```
09:48:14  remoteproc0 (modem) stopped        <- armed-edge test, clean
09:48:30  modem is now up
09:48:55  slim-ngd wakeup during SSR -> WCD9335 bringup fails
09:48:57  remoteproc2 (adsp) stopped         <- ADSP test, clean
09:49:02  adsp is now up
09:51:00  amixer -> slim_rx_mux_put -> Oops (WnR=1, addr 0x8)
```

☠️ **Retracted 2026-08-23 14:20, measured: the modem is not the trigger.** Six
modem restarts on r71 - five bare, one with a playback stream open across the
restart - produced **zero** codec failures. The first **ADSP** restart produced
the burst immediately (`CODEC version detection fail!`, `Failed to bringup
WCD9335`, 81 wcd9335 lines), which fits: the SLIMbus NGD master lives on the
ADSP, not on the modem. The earlier attribution came from reading one journal's
timestamps, where the modem's return happened to be the nearest preceding
event; it did not survive a controlled repeat. What stands is narrower and
still worth knowing: **an audio check run right after an ADSP restart may be
measuring wreckage.**

The same run is the first positive evidence for defect 1. The r70 crash
sequence - restart, then write `SLIM RX0 MUX` - has now run **four times on
r71**, once of them straight through the failure burst, with:

| round | codec-fail lines | mux write | oops | playback |
|---|---|---|---|---|
| 1 (with the burst) | 0 -> 2 | rc=0 | 0 | rc=0 |
| 2-4 | 2 -> 2 (no new burst) | rc=0 | 0 | rc=0 |

☠️ Still not proof: the damaged state was entered **once**, so n=1 for the path
that actually oopsed on r70. And the codec *recovered* here (version v2.0 read
back, card alive, playback fine) where on r70 it stayed down until reboot -
which is a difference neither fix explains, so it may simply be variance.

**Deployed as r71 (`#72-fp3`) and the device is healthy, but the crash itself
was not reproduced on the fixed kernel** — so the fixes are *not* proven, only
not-regressing. What the 2026-08-23 13:40 run measured:

| step | result |
|---|---|
| `SLIM RX0 MUX` written on a clean boot | no oops (would also have worked on r70) |
| modem stopped and restarted (`remoteproc0`, t=53.5 s / 57.4 s) | **no wcd9335 bringup failure at all this time** |
| mux written again afterwards | no oops, codec still answers |
| full battery | **31 ok / 0 failed / 3 skipped** — `24-speaker-amp` and `50-charger` green too |

☠️ The middle row is the problem: this modem restart did not damage the codec,
so the state that oopses was never entered. One clean pass is not evidence that
the fix works; it is evidence that the fault is intermittent, which was already
known. An attempt to force the state by unbinding and rebinding the codec
(`/sys/bus/slimbus/drivers/wcd9335-slim/{unbind,bind}`) does **not** reproduce
it either: the card disappears entirely, taking the mixer controls with it, so
there is nothing left to write. The oops needs the controls still exposed over a
codec whose channel map is gone, and that only happens on the SSR path. ☠️ That
unbind/rebind also costs audio until reboot.

**Defects 1 and 2 are written and pushed** (2026-08-23): `wip/7.1.3/audio`
`647cb5a1` + `2f4ea47a`, cherry-picked to `integration/7.1.3` and carried to
`debug-int/7.1.3` (`b5ae3e0f`), pinned as r71. Both compile clean; **neither is
verified on the device yet** — the proof is a modem restart followed by a mixer
write that does not oops, and a codec that still plays afterwards. Defect 3 is
untouched, so the second half of that test is expected to fail.

Not yet attempted, and worth asking before it is: write `SLIM RX0 Mux` on a
clean boot with no remoteproc restart at all, to see whether defect 1 fires on
its own. If it does, it is reportable to the LKML without any of this port's
context.


## ☠️ Defect 3, diagnosed: the codec ran its bring-up on the *absent* notification

**Measured 2026-08-23 on r71 (`#72-fp3`), clean boot, one `echo stop` to the
ADSP remoteproc addressed by name.** The device was rebooted first, because the
previous session's log held a 64-second restart loop whose phases could be read
two ways; that ambiguity is what a clean single restart removed.

The controller reports the codec absent before the restart and present again
afterwards, and calls `.device_status` for **both** edges
(`slim_report_absent()` → `slim_device_update_status()` →
`sbdrv->device_status`). `wcd9335_slim_status()` **never looked at the `status`
argument**, so the absent notification ran the entire bring-up against a bus
that was already down. From the capture, 1.0 s after the stop:

```
[74.809] qcom,slim-ngd-ctrl: HW wakeup attempt during SSR
[74.819] debugfs: '217:1a0:1:0' already exists in 'regmap'
[74.822] debugfs: '217:1a0:0:0' already exists in 'regmap'
[74.855] wcd9335-slim: WCD9335 CODEC version detection fail!
[74.862] wcd9335-slim: Failed to bringup WCD9335
         ... 78 lines of "Failed to write config eN" / "Failed to sync masks"
[82.05 ] wcd9335-slim: WCD9335 CODEC version is v2.0     <- the *present* edge
```

Three separate consequences, all from that one omission:

* **a register-map leak, once per restart.** The debugfs collision is the
  evidence: `regmap_init_slimbus()` runs again while the previous pair is still
  allocated, and nothing ever frees either. The boot-time bring-up has no such
  line; every bring-up after it does.
* **a bring-up that cannot succeed**, because the reads it needs return `-22`.
  ☠️ And `wcd9335_bring_up()` was testing *uninitialised locals* for a negative
  value — `regmap_read()` reports failure in its return code and leaves its
  output untouched — so the "version detection fail" message was firing by luck,
  not by detection.
* **no teardown at all**, so the interrupt chip from the previous bring-up stays
  installed and keeps retrying its mask writes into the dead bus.

**Why it sometimes recovers and sometimes does not.** When the absent edge is
followed by the controller unregistering, the codec device is unbound, the devm
resources are released, and the next present edge builds cleanly — that is the
recovering case, and it is what a single restart does. When a *second* present
notification arrives with no absent one in between, the retained interrupt chip
makes the next `request_irq()` fail and the codec never comes back:

```
genirq: Flags mismatch irq 142. 00002004 (wcd9335_pin1_irq) vs. 00002004 (...)
wcd9335-slim: Failed to request IRQ 142 for wcd9335_pin1_irq: -16
wcd9335-slim: error -EBUSY: Failed to register IRQ chip
```

☠️ Note the flags in that message are **identical** on both sides. That is the
signature of the same interrupt being requested twice, not of a flags
disagreement, and reading it as the latter costs an afternoon.

**The fix**, three commits on `wip/7.1.3/audio` (`aba7e40c`, `1d3ae998`,
`42b7e745`), cherry-picked to `integration/7.1.3` and carried to
`debug-int/7.1.3` `818d35f1`:

1. check the two `regmap_read()`s in `wcd9335_bring_up()` and propagate the
   error, instead of reading uninitialised stack;
2. split the callback the way `wcd934x` already does — bring up on
   `SLIM_DEVICE_STATUS_UP`, tear down on `SLIM_DEVICE_STATUS_DOWN`. The
   interrupt chip and the ASoC component move off `devm` so the teardown can
   release them: their lifetime is the **bus session**, not the driver binding.
   A `.remove` covers unbind without a preceding absent notification;
3. free the per-function interrupts in `wcd9335_teardown_irqs()`. They were
   `devm_request_threaded_irq()` on a device that never unbinds, and the
   teardown only wrote the port enable registers.

**What each revision measured, on the same one-restart test:**

| | r71 (`#72-fp3`) | r72 (`#73-fp3`) | r73 (`#74-fp3`) |
|---|---|---|---|
| `CODEC version detection fail!` | yes | none | **none** |
| `Failed to bringup WCD9335` | yes | none | **none** |
| `debugfs: … already exists` (the leak) | 2 per restart | none | **none** |
| `Flags mismatch` / `Failed to register IRQ chip` | on the non-recovering path | none | **none** |
| `remove_proc_entry` warning | n/a | 5 lines, 1 `WARNING:` | **0** |
| write storm | 78 lines, unbounded until re-register | 69 lines, bounded 37.50→38.98 s | 78 lines, bounded 36.46→38.10 s |
| playback at +0 / +20 s / +90 s | ok | ok | **ok / ok / ok** |

The r73 column was read twice from the same buffer by two different means -
the check script's counters and a plain `dmesg | grep -cE "WARNING|BUG|Call
trace"` - because the r72 round is exactly where one instrument said nothing
was wrong and the other found a warning.

☠️ **Step 2 introduced a warning that step 3 fixes**, and it was found only
because the reproduction script's own `dmesg` filter printed *nothing* while
`dmesg` itself held 225 codec lines. Two instruments, and the quiet one was the
one that agreed with the hypothesis — the same trap as the `find`-on-ccache
reading. Read `dmesg` directly.

**r73 (`818d35f1`, `#74-fp3`) is deployed and the acceptance test passes.**
Every codec-side row above is zero, on a buffer whose sanity rows (22 remoteproc
lines, 251 codec/SLIMbus lines) prove the restart really happened and the
counter really read it.

**The register-map leak is directly measured as fixed, not just absent.**
2026-08-23 on r73: a second bring-up was driven in the same boot (`WCD9335
CODEC version is` went 1 → 2 across a restart cycle) and
`debugfs: '217:1a0:1:0' already exists in 'regmap'` stayed at **0**. On r71
every bring-up after the boot-time one printed that pair; the boot-time one
never did. A second bring-up that does not collide is the leak being released.

☠️ **The `avs/audio` PDR route is ruled out as the trigger on this device.**
It was written up here as the likely second notification source and that was
wrong: `dmesg` says `PDM: no support for the platform, userspace daemon might
be required.` twice per boot, so the in-kernel pd-mapper does not serve
msm8953, `pdr_add_lookup(ctrl->pdr, "avs/audio", "msm/adsp/audio_pd")` never
resolves, and that branch of `qcom_slim_ngd_ssr_pdr_notify()` never fires here.
The reachable second source is narrower: `qcom_slim_ngd_notify_slaves()` runs
from the master worker whenever the controller is resumed while its state is
`DOWN`, and `slim_get_logical_addr()` → `slim_device_alloc_laddr()` ends in
`slim_device_update_status(sbdev, SLIM_DEVICE_STATUS_UP)`. A **runtime-PM
resume**, not only an SSR, can therefore re-report the codec present.

☠️ **An attempt to provoke that failed, and is recorded so it is not repeated
blind.** Audio traffic was held across a whole restart cycle (60 rounds of
playback plus a mixer read, spanning stop → +60 s) precisely to force resumes
in the window. The bring-up count still moved by exactly **one**. The window
between `ctrl->state = QCOM_SLIM_NGD_CTRL_DOWN` and the controller
unregistering is evidently too narrow to hit from userspace: once the
controller is unregistered there are no children for `notify_slaves()` to find.
Provoking it will need a kernel-side delay or a fault injection, not a busier
userspace.

☠️ **What is *not* proven:** the non-recovering path. Every controlled restart
run here - four on r71, one each on r72 and r73 - took the recovering path, so
the `-EBUSY` case that costs audio until reboot has still never been entered on
a fixed kernel. The fix removes its precondition by construction (the interrupt
chip no longer outlives the bus session) and that is an argument, not a
measurement. Provoking it needs two present notifications with no absent one
between them; the second source is the `avs/audio` PDR lookup alongside the
`lpass` SSR notifier, and `qcom_slim_ngd_ssr_pdr_notify()`'s UP branch has no
state guard where its DOWN branch does. That asymmetry is the next thing to
read.


## Open before anything is submitted

### ☠️ 2026-08-30 — a measured fix that is in NO submit series

`git diff fork/wip/7.1.3/audio fork/submit/7.1.3/audio` is **not** empty. Two
files differ, and only one of them is by design:

| file | why it differs | verdict |
|---|---|---|
| `drivers/i2c/busses/i2c-qup.c` | the amp-death pinctrl fix lives on `wip/audio` and on **`submit/7.1.3/i2c`** (`5560f875`), which is where it belongs | ✅ correct — a fix in a different subsystem goes to a different series |
| `sound/soc/codecs/snd-soc-aw8898.c` | `wip/audio` carries `55f6a643` *"ASoC: aw8898: mark SYSST volatile so the PLL poll can see it change"*. **No `submit/*` branch carries it** — checked across all seven | ☠️ **gap** |

**Why it matters more than a missing patch usually does.** The aw8898 driver is
not ours and not in mainline: it arrives on the base as a **FROMLIST** commit,
i.e. someone else's posted-but-unmerged series. That version sets
`cache_type = REGCACHE_MAPLE` and declares **no** `volatile_reg`, so every
register in the map is cacheable — including `SYSST`, which the driver *polls*
to wait for the PLL to lock. A poll of a cached register cannot observe a
change. We measured that defect and fixed it; the posted series still has it.

**So the action is not "add it to our series".** It is somebody else's unmerged
patch, and carrying a fix for it inside our audio submission would create a
dependency on a series that may never land, in the wrong direction. The upstream
move is to **reply to the aw8898 posting on the list** with the finding and the
one-line fix, so it is corrected at the source. Confirm the series is still
unmerged before writing, and cite the measurement rather than the diagnosis: the
control-bus reads that fail, not "we think the cache is wrong".

☠️ **And a reporting correction that goes with it.** Earlier the same day, after
regenerating `submit/7.1.3/audio`, the acceptance test was reported as
*"`git diff wip submit` is empty"*. It is not, and the check above is what the
claim should have rested on: a per-file account of what differs and why, since
on this port a submit branch legitimately drops things — an unsendable driver, a
fix that belongs in another subsystem's series. **"The diff is empty" is the
right test only for a category whose wip and submit really are the same set;
everywhere else it is the wrong test, and it passes or fails for reasons that
have nothing to do with the question.**


A red-team pass over the five `submit/7.1.3/*` branches on 2026-07-30 produced
this list. Everything here is measured — `checkpatch.pl --strict`, and
`dtbs_check` run against the base and against this tree so that only the errors
*we add* are counted (the base fails it 44 times on its own). The per-branch
summary is in [`kernel/README.md`](kernel/README.md#what-the-checkers-say).

~~**The camera series is the one that must not be sent as it stands.**~~ **Fixed
2026-07-30.** Its commit message claimed the driver was derived from `imx258.c`
with register tables read back from the sensor; both were false. The original was
found on GitLab (`sdm670-mainline/linux`, **Joel Selvaraj**, `5130bc702ea2`) and
fetched by SHA, the delta measured at **+68 / −21 on 1514 lines**, and the series
rebuilt as import → our change → device tree, with the original `Signed-off-by`
chain preserved. Details and the checkpatch split in
[`kernel/README.md`](kernel/README.md#camera-imx363c). The DCO chain turned out to
be **intact**, so the camera never had the sensor series' problem.

### ✅ DONE 2026-08-30 — `submit/7.1.3/audio` regenerated (was: fallen behind `wip`)

> Regenerated from `wip/7.1.3/audio` on 2026-08-30 (`0eed9f3d`): the five missing
> commits carried over, trailers swapped to the upstream form, two churn-only
> hunks dropped. The acceptance test is the one this table implies —
> **`git diff wip/7.1.3/audio submit/7.1.3/audio` is empty** — which is a
> stronger statement than any per-file count, because it cannot pass while
> anything is missing. Trailers audited: no `Signed-off-by` from the assistant
> anywhere in the series. The previous tip is reachable as
> `archive/submit-7.1.3-audio-pre-20260830`, tagged before the force-push, and
> the tarball for the package's pinned commit still answers 200.
>
> The analysis below is kept because its *method* is the reusable part: compare
> a reshaped series by **content**, never by patch-id — `git cherry` reports
> nearly the whole branch as missing here, since every id differs by
> construction, and reading that as a real gap would have sent someone hunting
> for commits that are present.

#### (done) The gap as it stood on 2026-08-29

The question that prompted the check was whether the audio work can go upstream
*before* the power work. On the power side it can — measured, see below — but the
series itself is stale, and the gap is real fixes rather than churn. Compared by
**content**, not by patch-id (`git cherry` reports nearly the whole branch here,
because the submit series is a reshaping of the wip commits and every id differs):

| file | `submit` vs `wip` | what is missing |
|---|---|---|
| `sound/soc/codecs/wcd9335.c` | **140+ / 32−** | the irq setup/teardown ordering, the chip-version reads being checked, the SLIMbus channel list heads initialised at probe, and the codec teardown when the SLIMbus device reports absent |
| `sound/soc/qcom/apq8016_sbc.c` | 8+ / 8− | the channel-map latch removal — the card-lifetime flag stops `dai_init` from ever reprogramming a codec that re-probed after an SSR |
| `sound/soc/codecs/wcd-mbhc-v2.c` | 1+ / 0− | a stray blank line; nothing to carry |
| `wcd9335.h`, `q6afe.c`, the board DTS, the binding | identical | — |

**The audio series does not depend on the power work.** The file sets are
disjoint: `submit/7.1.3/audio` touches `sound/soc/codecs/wcd*`, `apq8016_sbc.c`,
`q6afe.c`, the board DTS and the binding; `wip/7.1.3/power` touches clk, cpuidle,
irqchip, interconnect, regulator, rpmsg, slimbus and `msm8916-wcd-digital.c`.
Their intersection is **empty**. The two audio-scoped commits that live on the
power branch — the `msm8916-wcd-digital` mclk hold and the `qcom-ngd-ctrl`
`disable_stream` — are separate subsystems with separate maintainers and are not
in the audio series either way.

☠️ And on the consumption question specifically: the only audio-attributable power
suspicion, "the LPASS never sleeps", is **caused** by our audio boot path (proven
by blacklist bisection) and **worth no current** (A-B-A′, 30 min per leg: floor
52.9 / 56.3 / 54.6 mA — stopping the ADSP *costs* ~2 mA). What was never measured
is a boot with the audio stack absent, so the honest statement is "the audio stack
running is not expensive", not "audio adds nothing".

### ✅ 2026-08-29 evening — measured: the audio stack is not on the idle bill

| leg | audio stack | **floor p10** | median | MPSS awake |
|---|---|---|---|---|
| A | 4 modules, 1 card | **53 mA** | 100 | 37.5 % |
| B | **0 modules, 0 cards** | **55 mA** | 84 | 33.5 % |
| A′ | 4 modules, 1 card | **54 mA** | 134 | 51.4 % |

B is **above both of its controls**: removing the audio stack costs 1-2 mA rather
than saving any — the same direction and size as stopping the ADSP outright
(52.9 / 56.3 / 54.6, 2026-08-25). Two independent experiments, one removing the
DSP and one removing the drivers that talk to it, agree.

⇒ **The audio series goes upstream on its own schedule.** The remaining work on it
is the regeneration below, not a power dependency.

★ The same run is the sharpest case for reading the floor rather than the median:
the medians are 100 / 84 / 134 mA. Read them and the audio stack "saves 16 mA"; read
them in the other order and it "costs 50". ☠️ Resolution is about 2 mA and the phone
was idle — nothing here prices audio *in use*.

**The original plan, for the record.**
[`power/bringup/tools/audio-off-leg.sh`](power/bringup/tools/audio-off-leg.sh):
three boots, A (stack loaded) → B (`install <mod> /bin/false` for the card, the
digital codec, wcd9335 and the SLIMbus NGD) → A′, reading the **floor (p10)**
because the leg cannot run inside one boot and the median carries the modem's
per-boot offset. The leg's witness is the LPASS actually entering XO shutdown, not
the module list.

| result | what it means for the audio series |
|---|---|
| B floor within ~2 mA of the A/A′ bracket | the stack costs nothing measurable; the series goes upstream on its own schedule |
| B floor **below** the bracket by more than the bracket's own spread | the audio work carries a real idle cost, and it has to be understood — and probably fixed — before the series is sent |

☠️ Whichever way it reads, it is a statement about **our current audio stack on
this device**, not about the patches in isolation: the series contains fixes
(`disable_stream`, the mclk hold's siblings) that exist *because* of what was
measured here, so a positive result argues for sending them sooner, not later.

Then, in rough order of cost:

1. ~~**The camera has no binding and no MAINTAINERS entry.**~~ **Fixed
   2026-07-31.** `sony,imx363.yaml` is written, the MAINTAINERS block claims the
   driver, and the leftovers came out in a **third** commit after the import, so
   the imported commit stays byte-identical to Joel Selvaraj's original — that
   byte-identity is the only thing that makes our delta checkable.

   What the binding is worth is measurable, and the measurement is the point:
   until it existed, `dtbs_check` **skipped the camera node in silence**, because
   a node whose `compatible` nothing documents produces no output at all rather
   than being reported as unchecked. With the binding in place the node is
   checked for the first time and **adds nothing**: the board goes from the
   base's own 44 errors to 45, and the one addition is item 5's battery node,
   already known.

   Two places where copying `sony,imx258.yaml` would have been wrong. Its
   `data-lanes` pins the entries to 1..4; this driver only ever switches on *how
   many* there are, and 176 endpoints in mainline's arm64 device trees start
   their lane list at 0 — nearly every qcom board — so the value constraint would
   reject them for nothing. And imx258 leaves the supplies optional, where this
   driver takes all three with a plain `devm_regulator_bulk_get()`.

   The cleanup removed 97 lines: ninety-odd commented-out register writes, a
   dead 19.2 MHz input-clock path whose config table never existed, and two
   `printk(KERN_INFO)` calls. Two of those comments carried a **finding** rather
   than code — that a set of downstream writes, and a set taken from imx258,
   change nothing in the output — so they are kept as an ordinary comment.
   `checkpatch --strict` on the new patches: **0, 0 and 1**, the one being
   "does MAINTAINERS need updating?" which the next patch answers. The import's
   own 34 complaints are untouched on purpose.

2. ~~**The audio device tree adds six undocumented codec properties**~~ —
   `qcom,micbias{1..4}-microvolt`, `qcom,dmic-sample-rate`,
   `qcom,mbhc-vthreshold` on the `slim217,1a0` node. **Fixed 2026-07-30.** The
   WCD9335 binding now carries all of them, taking wording and limits from
   bindings that already describe the same hardware: the four mic-bias voltages
   verbatim from `qcom,wcd93xx-common.yaml`, the DMIC rate in the plain-uint32
   form the LPASS macro bindings use. The button thresholds were **renamed** on
   the way — `qcom,mbhc-vthreshold` in millivolts was this port's invention, and
   the rest of the family spells it
   `qcom,mbhc-buttons-vthreshold-microvolt` (wcd934x, wcd937x, wcd938x). The
   driver divides by 12500 instead of `(mV * 2) / 25`, so the value programmed
   into the BTNx field is unchanged. All six are disallowed on the SLIMbus
   interface device, where they mean nothing.
3. ~~**`divclk1` and `wcd-vout-1p8` sit under `soc@0`**~~, where `simple-bus`
   requires `ranges`. **Fixed 2026-07-30**: both moved to the root of the board
   file, and the regulator renamed to the `regulator-*` node-name form the file
   uses throughout.
4. ~~**`wcd-intr-default-state` fails the `qcom,msm8953-pinctrl` schema.**~~
   **Fixed 2026-07-30** by dropping `input-enable`, which
   `qcom,tlmm-common.yaml` disallows outright (`input-enable: false`): the TLMM
   input buffer is always on, so on this pin controller the property only ever
   cleared the output-enable bit, and gpio73 is put in input mode anyway when
   the codec's intr1 interrupt is requested. `sdm845-wcd9340.dtsi` describes the
   same codec interrupt without it.

   Items 2-4 were verified together rather than assumed: `dtbs_check` with
   `dtschema` 2026.6 reports **nothing** for the audio nodes now, on
   `wip/7.1.3/audio`, `integration/7.1.3` and `debug-int/7.1.3` alike, and
   sorted `dtc` decompiles of the board DTB before and after differ **only** in
   the two node moves, the dropped property and the renamed one.

   Confirmed on the device too, on `linux-fp3-7.1.3-r27`: the eight `BTN0..7`
   threshold registers read back **byte-identical** across the rename
   (`18 30 48 90 a0 a0 a0 a0`), the moved `divclk1` still claims the PM8953
   MCLK mux (`pin 0 (gpio1): divclk1 ... function func1`) and reaches
   `enable_count = 1` while playback runs over `SLIMBUS_0_RX`, and
   `23-audio-slimbus` passes with a headset plugged in — a 1 kHz tone crossing
   the bus in both directions, **999.76 Hz at 32.97 dB**. The jack still
   detects: `SW_HEADPHONE_INSERT` is active.
5. ~~**The battery node's `qcom,*` properties cannot stay there.**~~ **Moved
   2026-08-12**, in the shape `charger/README.md` had already argued for, as
   four commits: the generic property, the charger binding, the driver, the
   board.

   There were **five**, not four - the count in this item predated
   `qcom,auto-recharge-microvolt`. Four of them moved to the charger node: both
   JEITA threshold pairs, the soft-zone currents and the recharge voltage. The
   argument that decides it is not the schema but the layering: a threshold here
   is a **raw BAT_THERM ADC code**, and which code a temperature produces
   depends on the PMIC's ADC full scale and on the board's pull-up as much as on
   the cell, so it cannot travel with a pack. The battery-ID tolerance follows
   the pull-up onto the charger for the same reason - it has to cover the
   divider and the ADC, not only the resistor.

   The fifth stays with the pack, because the identification resistor really is
   inside it, and became the **generic `id-resistor-ohms`** added to
   `battery.yaml`. An ID resistor is not a Qualcomm idea, and a vendor-prefixed
   name on that node is rejected outright.
6. ~~**`-ohm` should be `-ohms`.**~~ **Done in the same commits.**
   `qcom,batt-id-ohm` is gone entirely (it is `id-resistor-ohms` now) and
   `qcom,batt-id-pullup-ohm` became `qcom,batt-id-pullup-ohms`. Nothing outside
   this tree can have been relying on either spelling: both are this port's own
   additions.
7. **Every branch is based on `v7.1.3-r0`.** Sending means rebasing first: ASoC
   onto `sound/for-next`, device trees onto mainline. Trial-rebased on
   2026-07-30, so this is no longer a guess: **11 of the 21 commits apply with no
   conflict**, the charger (9) and sensor (1) series entirely. Full table in
   [`kernel/README.md`](kernel/README.md#does-any-of-it-apply-to-a-maintainer-tree).
8. **The camera driver conflicts on two lines of `Kconfig`** — the neighbouring
   IMX355 entry gained `select V4L2_CCI_I2C` upstream. Trivial, but it has to be
   resolved by hand at rebase time.
9. **The audio series has a real prerequisite and it is stalled.**
   `qcom,msm8953-qdsp6-sndcard`, `msm8953_qdsp6_add_ops` and `use_ibit_clk` are
   not upstream; nor is the `&sound_card` label the audio DT patch attaches to.
   The functionality *was* posted — Adam Skladowski, *MSM8953/MSM8976 ASoC
   support* **v3**, 8 patches, 2024-07-31,
   [series 875540](https://patchwork.kernel.org/project/alsa-devel/list/?series=875540),
   still in state `new`. We need its patches 1/8, 5/8 and 6/8. Because it has a
   cover-letter message-id it can be declared as a dependency the way the kernel
   expects (`b4 prep --edit-deps`, or a `prerequisite-patch-id:` block) rather
   than silently assumed. Worth asking on the list whether it is still alive
   before building on it.
10. **The voice patch duplicates existing prior art and cannot be sent at all.**
    Joel Selvaraj's `5a63debde2db` (2022-10-02, `sdm670-mainline/linux`) already
    contains the same SLIMbus voice routing, line for line, and for SLIMBUS_0
    through SLIMBUS_6 rather than only SLIMBUS_0. Separately, `q6voice` has
    **never been posted to the LKML** — patchwork returns nothing for "q6voice"
    or "Q6 Voice" — so there is no message-id to depend on and the file does not
    exist upstream to patch. Archived as
    [`vendor/q6voice-sdm670`](https://github.com/llg179org/linux/tree/vendor/q6voice-sdm670);
    the realistic move is to offer the SLIMBUS_0 work to that series' authors
    rather than to send anything ourselves.
11. ~~**Two more WCD9335 properties are this port's invention, and their default
    is inverted.**~~ — `qcom,hphl-jack-type-normally-open` and
    `qcom,gnd-jack-type-normally-open`, against the family's
    `-normally-closed` spellings with the opposite default. **Fixed
    2026-07-31**, and the fix removed the question rather than answering it: the
    codec was moved onto the kernel's shared `wcd-mbhc-v2` (with a new legacy
    comparator backend, since this codec has no MBHC ADC), so it now calls the
    family's own `wcd_dt_parse_mbhc_data()`. Both invented names were deleted
    from the driver, from the binding and from the board file, and the board
    relies on the shared default — which is normally-open, the behaviour it
    already had. Verified with a headset on the device: a 4-pole headset, a
    3-pole headphone, the button and both removals all report correctly.
12. ~~**The measured rebase table no longer describes the audio series.**~~
    **Re-measured 2026-07-31**, all nine rows, against fresh bases
    (`broonie/for-next` `b8f7ea37085e`, `psy/for-next` `c57cb36f76eb`,
    `torvalds/master` `6269cc6f52c6`) and the regenerated thirteen-patch series:
    **22 of 27 commits apply with no conflict**, 23 after one one-hunk
    resolution. Audio went from "conflicts on the first patch" to **11/12** — the
    only conflict left is the machine driver, which is item 9's missing
    prerequisite and nothing else. Table in
    [`kernel/README.md`](kernel/README.md#does-any-of-it-apply-to-a-maintainer-tree).

    Two things the re-run corrected about the *method*, not the result. The
    camera's `Kconfig` conflict is no longer the IMX355 entry but `VIDEO_OV9282`:
    it lands on whichever entry sits next to ours, so naming the neighbour dates
    the note for nothing. And counting per commit while aborting each failure
    makes a cascade look like a catastrophe — the camera import fails on
    `Kconfig`, so the delta commit has no `imx363.c` to patch and the group reads
    **0/2** when the honest answer is one hunk, after which the second commit is
    clean.

13. ~~**`submit/7.1.3/audio` no longer matches the branch it is distilled
    from.**~~ **Regenerated 2026-07-31**, from thirteen commits: the binding, the
    machine driver, four wcd9335 fixes, q6afe, the OCP interrupts, the shared-MBHC
    work split three ways (function-table refactor with no functional change →
    legacy backend → the choice as a `wcd_mbhc_init()` parameter), the wcd9335
    conversion, and the device tree alone at the end. Every patch is
    single-domain; `checkpatch --strict` is clean apart from the two entries below
    that were checked and are not defects. The previous tip is the tag
    `archive/submit-7.1.3-audio-pre-mbhc-rework`.

    Three deliberate differences from `wip/7.1.3/audio`, none of them accidental:
    the `aw8898` `.prepare` fix is **excluded** (that driver is carried by
    msm8953-mainline and is not in Linus' tree, so it has no upstream destination
    in this series); the two q6afe commits are squashed into one; and the new
    `DEC*` volume controls are aligned to the open parenthesis while the
    pre-existing `RX*` ones above them are left exactly as mainline has them —
    the earlier series realigned those too, which is drive-by churn on code this
    work does not otherwise touch.

14. **Review feedback on the audio device tree — accepted in principle, not yet
    acted on.** An msm8953-mainline reviewer read the DTS commit
    (`2f76a315`, *wire up WCD9335 audio*) on 2026-08-02 and raised three things.
    Nothing below is implemented: each point needs the pro-and-contra written out
    and confirmed before anything is changed, because two of them touch the
    device tree the phone currently runs on.

    * **"Does it really have 6 digital mics?"** — no, and this one is already
      **measured**. The six-DMIC / AMIC1..6 block was transcribed from
      Fairphone's downstream `msm8953-audio.dtsi`, which is Qualcomm reference
      boilerplate: it also lists ANC headset mics, `Analog Mic6` and
      `SpkrLeft/Right IN`, none of which exist on this phone (the speaker is a
      single mono AW8898 on Quinary MI2S). Swept on the device with a 1 kHz tone
      from its own speaker, `DEC0` capture on `hw:0,1`, Goertzel at 1 kHz, three
      repeats per input:

      | input | 1 kHz bin | verdict |
      |---|---|---|
      | DMIC0 / DMIC1 | ~2200–2700 | live — bottom mic, next to the speaker |
      | DMIC2 / DMIC3 | ~520–630 | live — top mic, 5× quieter because it is further away |
      | DMIC4 / DMIC5 | exact 0 (3/3, every run) | not populated |
      | AMIC2, headset plugged in | 1437 | live — headset mic |
      | AMIC2, empty jack | 0.25 | noise floor only |
      | AMIC1, 3, 4, 5, 6 | exact 0 | not populated |

      The headset gives the positive control the first sweep lacked: AMIC2 moves
      from noise floor to 1437 while every other analog input stays at exact
      digital zero, so those zeroes are absence, not a broken measurement.
      `wcd9335_codec_enable_dmic()` maps DMIC0/1 → `CPE_SS_DMIC0_CTL`, DMIC2/3 →
      `DMIC1_CTL`, DMIC4/5 → `DMIC2_CTL`, i.e. three clk/data pad pairs of two
      channels each — so **two populated DMIC lines, which is exactly the two
      built-in mics the FP3 has**, and the odd slots are the same data line read
      on the other edge.

      Two corrections fall out of this. `"AMIC5", "MIC BIAS3"`, which the commit
      message describes as the handset mic, is **measurably wrong** — AMIC5 is
      dead and the built-in mic is DMIC0, which is also what
      `fp3-mic-select handset` uses. And `qcom,micbias4-microvolt` has nothing
      left to bias.

      ☠️ **Measurement trap for whoever redoes this:** individual captures
      occasionally return exact digital silence (the decimator power-sequencing
      quirk described in
      [`../userspace-audio/README.md`](../userspace-audio/README.md)), and on
      back-to-back mux changes the previous value leaks into the next reading —
      DMIC3 came out identical to DMIC2 in two separate sweeps. Repeat at least
      three times per input and do not conclude from a single run.

    * **"Only one other sdm632/sdm450 device tree defines `audio-routing`, and
      not with a list this long."** The comparison is against the wrong family
      and the answer is defensible: every other msm8953/sdm450 board drives the
      **PM8953 internal codec**, whose routes live in the codec driver, so three
      `AMIC → MIC BIAS` lines suffice. FP3 is the only msm8953 board with an
      external WCD9335 over SLIMbus, where `MCLK` and `MIC BIAS1..4` are
      `SND_SOC_DAPM_SUPPLY` widgets with no in-codec route, so the board has to
      pull them in. The precedent is on the msm8996 side —
      `msm8996-oneplus-common.dtsi` and `apq8096-db820c.dtsi`. The *length*,
      though, is only justified for the inputs that exist, so this point is
      settled by the DMIC pruning above rather than argued away.

    * **"The wcd9335 codec node looks weird too — any similar examples?"** Yes,
      and the node is near-verbatim from them: `msm8996-xiaomi-common.dtsi`
      (same `slim217,1a0` `codec@1,0`, `slim-ifc-dev`, `intr1`/`intr2`,
      `reset-gpios`, mclk + slimbus clocks, the `vdd-*` set, and a `divclk1`
      `gpio-gate-clock` even carrying the same `divclk1_cdc` label),
      `apq8096-db820c.dtsi`, `msm8996-oneplus-common.dtsi`,
      `msm8996pro-xiaomi-{natrium,scorpio}.dts`. Only the msm8953 addresses and
      the FP3 supply/GPIO/pinmux instantiations are new, because no msm8953
      board in-tree instantiates the SLIMbus NGD at all. **One genuine defect
      surfaced by the question:** on msm8996 the `slimbam` and `slim_msm` nodes
      live in the SoC `.dtsi` (`msm8996.dtsi`) and the board only writes
      `&slim_msm { ... }`; ours sit in the board `.dts` under `&soc`. They
      belong in `msm8953.dtsi`, status `disabled`, with the board enabling them
      and adding the codec child.

    The reviewer also confirmed the quinary DAI link is fine as it stands.

    **What a v2 would be**, once confirmed: cut `audio-routing` to `RX_BIAS`/
    `MCLK`, AMIC2 on MIC BIAS2, DMIC0 on MIC BIAS1 and DMIC2 on MIC BIAS3; drop
    `qcom,micbias4-microvolt`; move the NGD/BAM nodes to `msm8953.dtsi`. It
    touches `wip/7.1.3/audio`, `integration/7.1.3` and `debug-int/7.1.3`, and
    the mics have to be re-measured on the device afterwards, since the pruned
    routes are the ones that power the capture path. Open sub-question, not
    needed for the pruning but worth one test: which slot of each pad pair is
    the real capsule — covering one mic port and re-sweeping answers it.

15. **Review feedback on the audio *driver* commits — nothing implemented, each
    point needs confirming first.** The same reviewer read three commits of
    `wip/7.1.3/audio` on 2026-08-02 — `ca9aaa72` (mic bias and DMIC rate from
    the DT), `377269e4` (the TX front-end hold) and `254359e1` (MBHC jack
    detection) — and checking the comments turned up five more things we found
    ourselves. As in item 14, none of it is done, and each point is written with
    the argument against it, because three of them are cheaper to get wrong than
    to leave alone.

    One question the pass raised is **already answered**: *"where are
    `qcom,micbias1-microvolt` … and `qcom,dmic-sample-rate` defined? I can't see
    them in the bindings."* Item 2 above — the binding has carried all six since
    2026-07-30. What misleads a reader is that `wip/7.1.3/audio` is
    discovery-ordered, so there the driver commit precedes the binding commit; on
    `submit/7.1.3/audio` the binding is patch 1 of 13. Nothing to change, but the
    reply has to say so.

    * **A bare `BIT(2)` goes into `WCD9335_CODEC_RPM_CLK_MCLK_CFG`** in
      `wcd9335_codec_init()`, where every other field in this driver has a named
      macro in `wcd9335.h`. *Against naming it:* we cannot name it **truthfully**
      — there is no datasheet, and downstream has no name either, only an
      unnamed `tasha_codec_reg_defaults[]` entry (`{MCLK_CFG, 0x04, 0x04}`, and
      `0x05, 0x05` in the I²C variant, so the bit is independent of the MCLK
      rate). A confident invented name is the mistake of item 11 repeated. The
      honest options are a neutral name plus a comment saying the function is
      undocumented, or an A/B on the device to find out whether the write is
      needed at all — the commit claims garbled playback without it, and that
      claim is not backed by a recorded measurement. Two adjacent
      `regmap_update_bits()` on the same register should become one either way.
    * **The `0x20` written into the EFUSE sense-state field is a dead value.**
      `WCD9335_CHIP_TIER_CTRL_EFUSE_SSTATE_MASK` is `GENMASK(4, 1)` = `0x1e`, so
      `0x20 & 0x1e == 0`: the call clears bits 4:1 and does nothing else. That
      happens to be the intended "select state 0", but the constant reads as
      "set bit 5". Writing `0` is arithmetically identical, so **no device time
      is needed**. The oddity is inherited, not ours — downstream does the same
      `0x1E, 0x20` — so the only argument against is that it stops being a
      verbatim copy, which a comment covers. Cheapest item here.
    * **`WCD9335_CODEC_RPM_CLK_MCLK_CFG_12P288MHZ` is `BIT(0)`**, the same as
      `_9P6MHZ`; downstream writes `0x03,0x00` for 12.288 MHz, so it should be
      `0`. Pre-existing upstream, independent of this series, and a clean
      standalone patch. *Against:* the define is **unused**, so a maintainer may
      prefer deleting it to fixing it, and a patch found by reading rather than
      by measuring is easy to read as noise. Low priority, own submission cycle.
    * **The `usleep_range(1000, 1100)` before the TX-hold release has no cited
      source.** It runs per-ADC on every wcd9335 board. Downstream has no sleep
      at that site — its settle time came from the HPF delayed work's scheduling
      delay, which mainline dropped along with the release itself. *Against
      touching it:* removing it risks bringing back the silent capture this
      commit fixes, and proving that costs cold-boot A/B time on the device.
      Keeping it with a measured justification is an acceptable outcome; keeping
      it with none is not. The same commit message should also say why the
      release sits in the ADC widget's `POST_PMU` and not the decimator's — DAPM
      powers the decimator and its mux first, so the amic lookup there runs
      before the analog front end is up. Without that sentence the first review
      comment will be "move it to the decimator handler".
    * **The reviewer asked for a table instead of the `switch`** in
      `wcd9335_get_dmic_clk_val()`. Cheap, no functional change, and the six
      `WCD9335_DMIC_CLK_DIV_*` values are `0x0`–`0x5` in the same order as the
      dividers `{2, 3, 4, 6, 8, 16}`. *Against:* the `switch` is a deliberate
      copy of mainline `wcd934x_get_dmic_clk_val()` (`wcd934x.c`, same divider
      set, same fallback), and converting only ours ends the symmetry that makes
      folding both into one helper obvious later. Converting wcd934x too doubles
      the work on a driver **we cannot test**. Decide which, do not drift into it.
    * **The MBHC provenance needs checking, not patching.** `254359e1` links the
      v3 **cover letter** of Srinivas Kandagatla's 2018 WCD9335 series, which
      never mentions MBHC — hence the reviewer's "I cannot find references to
      the MBHC support dropped from the series". It is there: MBHC is patch
      11/13 in v3 and 11/14 in v4 (patchwork
      [10587057](https://patchwork.kernel.org/patch/10587057/), with its bindings
      patch [10587061](https://patchwork.kernel.org/patch/10587061/)), gone in v5
      (8 patches), and v6 — also 8 — is what was accepted, which is why mainline
      has never carried MBHC. But `254359e1` is a **superseded** commit: item 11
      replaced that private implementation with the shared `wcd-mbhc-v2`, and
      `f5759717`, the legacy comparator backend, cites only its OnePlus
      downstream source. So the open question is not the broken link, it is
      whether **anything** in `f5759717` derives from the 2018 patch. If it does,
      it must be cited; if it does not, adding the citation would be a false
      derivation claim — the camera mistake in mirror image.

      **Read and answered 2026-08-08: nothing derives from it, so it must not be
      cited.** The two are different code, not two versions of one. Kandagatla's
      10587057 touches `wcd9335.c` and nothing else — a codec-private
      implementation (`wcd9335_mbhc_sw_irq`, `wcd9335_mbhc_btn_press_irq`,
      `wcd9335_program_btn_threshold`, `wcd9335_mbhc_initialise`), with no
      reference to `wcd-mbhc-v2` or `wcd-mbhc-legacy`. `f5759717` adds a backend
      to the shared `wcd-mbhc-v2.c` through its function table, in the
      `wcd_mbhc_*` namespace, ported from OnePlus's `wcd-mbhc-legacy.c`
      (Copyright 2015-2017 The Linux Foundation) — a different file, a different
      namespace and a different integration model. The one thing they share is
      the comparator-and-current-source FSM instead of an ADC read, and that is
      dictated by the hardware — the WCD9335 has no MBHC ADC — and traces to the
      common Linux Foundation downstream that predates both, which each derived
      from independently. So the reviewer reply states this and adds no
      Kandagatla citation; citing him would be the false-derivation mistake the
      camera series taught, run in reverse.
    * **The TX-hold fix is codec-wide, and one other mainline board notices.**
      Mainline takes the hold in `wcd9335_codec_enable_adc()` and never releases
      it, so the change cannot regress anyone: it supplies a missing half. By
      inspection of the device trees — not measured, and it has to be worded that
      way — `msm8996-oneplus-common.dtsi` is the only other wcd9335 board wiring
      analog mics (AMIC2/4/5), so OnePlus 3/3T gain working analog capture, while
      `apq8096-db820c.dtsi` and the Xiaomi msm8996/msm8996pro boards declare no
      AMIC routes and their ADC widgets never power up. Worth stating in the
      cover letter and worth a Cc to the OnePlus 3 maintainers, who have hardware
      we do not. *Against:* a Cc invites a wait, and an unverified cross-board
      claim is worse than none — hence "by inspection".

    **Order, if any of it is confirmed:** the EFUSE constant first (no device
    time, no judgement call), then the DMIC table and the cover-letter wording,
    then the provenance read. The `BIT(2)` naming and the 1 ms sleep are last
    because both really want a measurement, not a decision.

Two things were checked and are **not** defects: the three `ENOTSUPP`
comparisons in the audio machine driver (the ASoC core returns exactly that, and
the base file plus six other qcom machine drivers compare against it), and the
undocumented `slim217` vendor prefix (absent from `vendor-prefixes.yaml`, but
already used by four device trees in Linus' tree).

## Licence and provenance

An audit on 2026-08-02 asked one question — *is anything in this work copied from
closed-source Android code, or otherwise carried under the wrong licence?* — and
walked all five `wip/7.1.3/*` categories, the SPDX header of every `.c`/`.h` they
touch, the authorship of every import commit, and the provenance tables in
[`kernel/README.md`](kernel/README.md#provenance) and
[`sensors/README.md`](sensors/README.md#provenance).

**The headline is negative: there is no closed-source Android driver in the fork
and no file carried under the wrong licence.** Every source file the five
categories touch is GPL-2.0 by SPDX — the single exception,
`scripts/mod/file2alias.c`, carries no SPDX line upstream either and this work
adds ten lines to it. No firmware blob is checked into either repository; the
ADSP, modem and WCNSS images stay on the phone's own partitions and are
referenced by name.

What the audit did find, in descending order of exposure. **None of it is acted
on**; each item needs its pro and contra written out and confirmed first, and the
first one is a legal judgement rather than a technical one.

1. **`drivers/media/i2c/lc898217.c` is the one part derived from closed
   source.** The actuator's whole register interface — slave address, address
   and data widths, position register, code width, power-up write — was read out
   of `libactuator_lc898217xc.so`, the proprietary vendor userspace library
   shipped with this board's Android firmware. There was no GPL source to take
   it from: Qualcomm's downstream keeps no register map in the kernel for this
   part at all (the node is a bare `qcom,actuator` with a CCI master number, and
   the generic engine in `msm_actuator.c` is fed the map from that library over
   an ioctl), and searching the downstream tree for the part number returns one
   hit, an unrelated string in `sound/pci/hda/patch_realtek.c`.

   In favour: what came out is a hardware register map for a **third-party ON
   Semiconductor part** — facts about hardware, not expression; it was read from
   the library's `.data` section rather than decompiled; and the decode was
   validated against a known answer (the same layout applied to
   `libactuator_dw9714.so` reproduces, field for field, what `dw9714.c` already
   does in-tree, and recovers that part's documented power-up sequence). The EU
   Software Directive's Article 6 interoperability exception and the US
   *Sega v. Accolade* / *Sony v. Connectix* line both point the same way, and the
   kernel takes reverse-engineered drivers routinely. The method is stated in the
   commit message rather than left implicit, which is the right shape.

   Against: any EULA on the firmware is a separate, contractual question that
   none of the above answers, and on the LKML this is the point a maintainer will
   ask about first. ☠️ **This is a decision for a human, not something to resolve
   by writing a better commit message.**

2. **The imported sensor base cannot carry a DCO.** `bc02a8f70f69` *WIP: iio:
   Add Qualcomm Sensor Manager driver* and `e4f194b29e8a` *WIP: iio: accel: …*
   are Yassine Oudjana's code and carry **no `Signed-off-by` at all**, not even
   his own. The licence is fine — GPL-2.0-only by SPDX — but the certification
   chain is not, and only he can supply it. His other two QRTR commits are
   properly signed off. Already the first of the three reasons
   `submit/7.1.3/sensor` is a single patch; see
   [`sensors/README.md`](sensors/README.md#why-the-submit-series-is-one-patch).

3. **Checked and clean, recorded so the question is not reopened.**
   `imx363.c` is Joel Selvaraj's reverse-engineering work under GPL-2.0, keeping
   `Copyright (C) 2018 Intel Corporation` from the driver it is structured on,
   and the import preserves the full chain (Joel → panpanpanpan → Richard Acayan
   → us). Every value taken from the vendor — DT addresses, mic-bias voltages,
   the DMIC rate, the JEITA thresholds, the actuator inversion in
   `msm_actuator.c` — comes from Fairphone's **published GPL kernel release**,
   the same licence as the files it lands in. `qcom_smbx.c`, `wcd9335.c`,
   `wcd-mbhc-v2.c`, `apq8016_sbc.c`, `q6afe.c` and `q6voice-dai.c` are all
   in-place extensions of GPL code that was already in the base.

4. **Four compliance gaps in this repository**, none in the kernel fork, all of
   them small:

   * There is **no `LICENSE` or `COPYING` file**. The
     [top-level README](../README.md#license) states GPL-2.0-only and nothing
     else does.
   * [`device_tree/downstream/fairphone/3.A.0136/`](device_tree/downstream/fairphone/3.A.0136/)
     redistributes 938 of Fairphone's GPL-2 device-tree files. Each one keeps its
     Linux Foundation copyright and GPLv2 notice — checked, not assumed — but
     **the licence text is not shipped alongside them**, which GPL-2 §1 asks for.
     Copying in a `COPYING` closes it.
   * [`sensors/bringup/data/sns.reg`](sensors/bringup/data/sns.reg) and the 1437
     pairs decoded from it in
     [`../userspace-sensors/registry.conf`](../userspace-sensors/registry.conf)
     are the phone's factory sensor registry — third-party vendor data, under no
     stated licence, in a public repository.
   * [`../userspace-sensors/groups.txt`](../userspace-sensors/groups.txt) is the
     group map taken from upstream
     [`sns-reg`](https://gitlab.com/msm8996-mainline/sns-reg)'s `map.c`, and
     **that project's licence is recorded nowhere here**.

   The libcamera and Snapshot changes are shipped as patches against their own
   upstreams, so they raise nothing.

Separately from licensing, the AI-authorship policy is already settled and needs
no work: local fork commits carry `Co-authored-by: Claude`, anything prepared for
the LKML carries `Assisted-by:` and never a `Signed-off-by` from the assistant.
That is also why the LKML is the only open destination — see
the by-branch view below and the top-level README.

## Holding the camera open costs ~100 mA of idle current

Measured 2026-08-13, and it accounts for most of the pmOS-versus-Ubuntu-Touch
idle gap: three twelve-minute phases on one discharge, one change between each,
72 samples apiece — **166 mA as found, 68 mA with the camera released**, and
stopping wireplumber outright saves nothing beyond that. Full numbers and the
two explanations that were tested and failed (it is not CPU, and `clk_summary`
is identical) in [`power/README.md`](power/README.md).

The mechanism is a pair of behaviours that are each defensible alone:

* `ak7375_open()` takes a runtime-PM reference, so **opening** the subdev powers
  the voice-coil motor — the upstream pattern for VCM drivers;
* libcamera's pipeline handler keeps every device of a camera open for as long
  as the `CameraManager` lives, and wireplumber keeps one alive to publish the
  camera to PipeWire.

Together they mean a phone with an autofocus motor pays for it whenever anything
enumerates cameras, whether or not a picture is ever taken.

☠️ **Disabling wireplumber's `monitor.v4l2` / `monitor.libcamera` is the
measurement, not the fix** — it removes the camera from PipeWire entirely. What
a fix looks like is the open question, and the options sit in different projects:
have libcamera close the subdevs when no camera is acquired; give the actuator an
autosuspend delay so an idle open costs nothing; or have the session manager
enumerate and then let go.

**Which of them is worth doing is now measured.** The hold was split on
2026-08-13, using a bare shell as the holder (`sh -c 'exec 3</dev/v4l-subdev17;
sleep 100000'`) so that exactly one node is open per phase — three more
twelve-minute phases on one discharge
([capture](power/bringup/captures/2026-08-13_pmos_lens-vs-chain.txt)):

| phase | held open | median current | median power |
|---|---|---|---|
| P0 | nothing | 79.7 mA | 0.342 W |
| **P1** | **the `ak7375` subdev alone** | **152.4 mA** | **0.643 W** |
| P2 | `media0`, `video0`, CSIPHY/CSID/ISPIF/VFE, `imx363` — all but the actuator | 76.4 mA | 0.323 W |

P2 lands on P0: **the sensor and the whole CSI/VFE front end cost nothing while
merely open, and the entire hold cost is the lens motor** — +0.30 W on its own,
with `cam_af_2p85`/`cam_io_1p8` `enabled` in P1 and `disabled` in both others.

So the fix belongs in **`ak7375`**: `ak7375_open()` takes the runtime-PM
reference and only `ak7375_close()` drops it, so the motor is up for as long as
any file descriptor lives. Closing the subdev in libcamera would work too, but
it treats the symptom in one consumer while the driver keeps charging every
other one.

☠️ **Adding an autosuspend delay is not the fix**, however much it sounds like
one: autosuspend acts when a device goes idle, and this device never does — the
reference is held, not slow to expire. ☠️ **And moving the reference to the
position write with a delay after it is not the fix either** — a voice coil
holds its position only while driven, so a timer expiring under a focused
preview would let the spring pull the lens out of focus.

**Written and measured 2026-08-13.** Power follows the **requested position**: a
reference is taken for the first position away from rest and dropped when the
lens is asked back to it. Focus is never lost, because a non-zero position keeps
the reference; idle costs nothing, because idle *is* the rest position.
Hot-swapped into the running kernel and measured with the same phases: **holding
the subdev costs +2.8 mA / +0.011 W**, against +72.7 mA / +0.30 W on the stock
driver ([capture](power/bringup/captures/2026-08-13_pmos_ak7375-position-power.txt)).

What is left on it:

* **the autofocus regression is unrun** — a real capture must still focus and
  *hold* focus. It could not be done in the swap session: unbinding the subdev
  left the media graph inconsistent (`Failed to find MediaObject with id 0`) and
  libcamera stopped enumerating the camera until a reboot. Note that `cam` alone
  does not exercise AF — `focus_absolute` stays 0 — so this needs the AF path
  the camera app uses;
* **the verdict must come from a package build**: `insmod` of a locally built
  module raised an `ftrace_bug` warning. It is a hot-swap artefact, but it makes
  the vehicle unfit for a final answer;
* **`driven` is one flag shared by all consumers**, so with two opens a
  `close()` could drop the reference out from under the other. Consumers are
  single here, but this has to be resolved before the driver goes to
  `linux-media`, where other boards use it.

Left open underneath all of it: why a VCM that is powered and commanded nowhere
dissipates a third of a watt at all — a question about the part, and the only
one a rail probe could still answer.

☠️ Compare those phases against the earlier A/B/C **in power, not in current**:
they ran at a different state of charge, and the same power draws less current
at a higher terminal voltage.

☠️ Kill such holders **by PID found in `/proc/*/fd`**: `pkill -f` matches the
very SSH command line that carries the pattern, and kills the shell issuing it —
silently, with no output and no error.

## The night harness parks the phone at the greeter, defeating the autologin

Observed 2026-08-22, at the end of the overnight suspend legs. The measurement
scripts (`suspend-leg.sh`, `suspend-slope.sh`) stop `greetd` for the window and
restart it on exit. After that restart the phone sits at the **phrog greeter**
(password screen), not in the auto-logged-in phosh session: the journal shows
the restarted greetd opening the greeter session (`user greetd(uid=113)`)
immediately, with no PAM activity for `fp3` — so `[initial_session]` in
`/etc/phrog/greetd-config.toml` did not run on that start, only the
`default_session`. Its own comment says "the session to be used on boot", and
that is how it behaved.

Consequences, both observed the same morning:

* after every unattended night the phone waits at a password screen until a
  human logs in — the selftest battery's autologin premise
  (`03-autologin`) silently does not hold for the post-leg state;
* an incoming call still rings there (gnome-calls runs in the greeter session
  too, which is the desirable half), but answering/unlocking runs into the
  ~80 s manual-login bring-up, which reads as a frozen GUI. A first PAM attempt
  rejected during that window (`AUTH_ERR`, then the retry succeeded) is what a
  2026-08-22 test call looked like from the outside.

~~Open questions, in test order: does greetd re-run `[initial_session]` on a
plain `systemctl restart greetd` on this version at all~~ — **answered
2026-08-22, measured: it does not.** A plain restart brings up the phrog
greeter (`loginctl` class `greeter` on seat0), so the autologin fires on boot
only, and every harness restore lands at the password screen by design of the
config. The restore step therefore has to do something else — either whatever
boot does, or stop stopping greetd and lock the session instead. Also
worth checking: the monotonic-clock trap while reading this journal —
`short-monotonic` does not advance across suspend, so post-leg timestamps look
hours old; compare against `/proc/uptime` (boottime) before dating any event.

### The same night also strands PulseAudio with the card profile `off`

Second symptom, same morning, found when a test call had no ringback and the
volume control showed "Dummy output". The kernel card was fine and every
profile probed as available (`HiFi (Speaker)` etc. `available: yes`), but the
session's PulseAudio held `Active Profile: off`, had produced only the
`auto_null` sink, and **silently ignored `pactl set-card-profile`** — no error
returned, no line logged, no sink created. The instance was started the
previous evening (socket dir timestamped 23:06) and had lived through the
legs' ~5 h of suspends and two greeter/session cycles. `pulseaudio -k` fixed
it outright: the respawned daemon came up with `HiFi (Speaker)` active and a
real sink, confirmed audibly with a 1 kHz tone.

Consequences worth spelling out: a call *rings* in this state (the modem side
does not need the AP's audio card) but has no ringback, no speakerphone and no
audible path — which is what the earlier "the speakerphone button did not
work" report actually was. So the harness restore step has two jobs, not one:
bring back the session (the autologin question above) *and* leave it with a
freshly spawned audio stack — or at minimum the morning-after check should
assert `pactl list sinks short` shows a real sink, which is a one-line probe
the selftest battery could carry (the audio checks all talk to ALSA directly,
so they stay green while every desktop application is deaf).

Both cheap single-shot discriminators came back negative the same day, which
narrows the reproduction rather than the suspect list: with a healthy PA, one
900 s s2idle with no session cycle left the sink and profile intact
(`suspends=1`, verified), and one `systemctl restart greetd` with no suspend
tore the session down, restarted the user's PA — and the fresh instance came
up *correctly*, real sink, `HiFi (Speaker)`. So neither a single suspend nor a
single session cycle strands it; whatever does needs the full overnight
pattern — repetition, the combination, or the 07:41 `module-alsa-source`
failure cascading — and reproducing it costs a night, not fifteen minutes.

## `pd-mapper.service` is permanently failed, and the RTC cannot be set

Two findings from one investigation, 2026-08-14. Neither is urgent; both are
written down because each looks like something worse than it is.

### `pd-mapper` — nothing to serve, and a restart policy that gives up

`systemctl` reports it `failed (Result: start-limit-hit)`. Run by hand it says
what it means:

```
# /usr/bin/pd-mapper
no pd maps available
```

It reads the protection-domain map files the vendor firmware ships, and
`find /lib/firmware -name '*.jsn'` returns **zero** on this device — the FP3
firmware carries none. The package ships only the binary
(`apk info -L pd-mapper` → `usr/bin/pd-mapper`), so there is nothing to supply
them either. The unit then has `Restart=always` with no `RestartSec` or
`StartLimit` tuning, so it burns the default five restarts in ten seconds and
stops for good.

**Nothing is broken by it.** All three remoteprocs are `running`, and the two
subsystems that would care — audio over APR and the SSC sensors over QMI — work.
On this SMD-era SoC nothing asks for a PD map. The honest fix is to **disable the
unit rather than repair it**, and the reason to bother at all is that a
permanently-failed unit is noise in `10-health`, which asserts no new failed
units.

### The RTC is read-only, which is why the failure looks a month old

`systemctl` dates the failure to 2026-07-15 — four weeks before a boot that
happened eleven hours earlier. The clock explains it:

```
# date                → Fri Aug 14 17:13:07 CEST 2026
# uptime -s           → 2026-08-14 06:09:34        (agrees with /proc/uptime)
# hwclock -r          → 1970-01-01 12:03:46
# hwclock -w          → ioctl(RTC_SET_TIME) ... failed: No such device
```

The hardware clock never advances past the epoch, so early boot runs on a
fictional date until NTP corrects it, and anything that fails before then is
stamped with that fiction. `rtcwake` is unaffected — an alarm is relative to
whatever the counter reads — which is why the suspend work never noticed.

**Why it cannot be set**, from `drivers/rtc/rtc-pm8xxx.c`: mainline offers three
ways to persist time and the FP3 device tree enables none of them. Without
`allow-set-time` the driver takes the offset path (`:353`), and
`pm8xxx_rtc_update_offset()` returns `-ENODEV` immediately when there is neither
an `offset` nvmem cell nor `qcom,uefi-rtc-info` — which is exactly the error
`hwclock` printed. Our `rtc@6000` node (`pm8953.dtsi:106`) has none of the three.

☠️ **`allow-set-time` is the tempting one-line fix and the wrong first move.** On
Qualcomm the RTC counter is commonly owned by the secure world, so a direct write
can fail or be silently discarded; the offset-in-nvmem path exists precisely
because of that. Establish first whether pm8953 exposes an SDAM cell for it —
and check what the vendor kernel does on this board — before adding a property
and declaring victory.

### The cellular network already supplies the time, and nothing consumes it

Measured 2026-08-14, registered on Vodafone HU at 78 % signal. This is NITZ,
carried on the signalling channel — **no mobile data and no data subscription are
involved**, which makes it the one time source available when there is no WiFi:

```
# mmcli -m 0 --time            (needs root; polkit refuses the plain user)
  Time     | current: 2026-08-14T15:37:52+02
  Timezone | current: 120
```

☠️ **The value is UTC and the string labels it as local.** Real local time at
that instant was 17:37:53 CEST, so UTC was 15:37:53 — which is what the modem
reported, to the second. The appended `+02` claims it is already local, so
anything parsing that string at face value sets the clock **two hours slow**. The
offset itself is separately reported and correct (120 minutes). Whether this is
ModemManager's assembly or the QMI plugin is not established; what is established
is that the two fields are individually right and the composed string is not.

**The shape of a fix that is safe without resolving that.** Use it only as a
bootstrap: if the system clock is near the epoch — the state this device boots
into every time — set it from the network value; if the clock is already
plausible, do nothing. A two-hour error is irrelevant against 1970, and it is
enough to make TLS, `apk` and log timestamps work until NTP refines it. That way
the ambiguity above never has to be decided, and the rule stays simple enough to
be correct on any phone and any operator.

~~Not yet established, and both are cheap reads: whether anything currently
consumes the value at all, and how long after boot the modem can first
answer.~~ **Both measured, and the bootstrap is written — 2026-08-16.** It is
[`userspace-system/fp3-nitz-clock`](../userspace-system/README.md#fp3-nitz-clock--a-real-date-on-a-phone-with-no-writable-rtc),
with `71-clock` in the battery to keep it from being lost again. What the two
reads answered:

* **registration takes about 42 s** from boot (`registering -> home` at
  17:11:03 for a boot at 17:10:21), so the bootstrap waits for the modem rather
  than running at a fixed point;
* **nothing consumed the value, and on that boot nothing could have.** The
  `org.freedesktop.ModemManager1.Modem.Time` interface was absent from the
  modem's D-Bus object for the whole session — `mmcli -m 0 --time` answered
  *"modem has no time capabilities"* — while the modem was registered on LTE at
  75 % signal with the packet service attached. Restarting ModemManager, or
  disabling and re-enabling the modem, brought it back immediately, with
  `modem has time capabilities, enabling the Time interface` and QMI
  `Get Network Time` traffic following.

☠️ **That last one is still open, and it is the interesting half.** The
capability check looks as though it is decided once, early, and comes out
negative when it runs before the modem can answer — but that is a hypothesis
from a single boot, not a measurement of the mechanism. If it turns out to be
reproducible, the bootstrap will find nothing on a cold boot no matter how long
it waits, and the fix belongs in ModemManager rather than in a script of ours.
The cheap next read is the next reboot: does the interface come up on its own?

The `allow-set-time` / RTC half of this section is untouched by any of it — the
clock still does not survive a reboot, and the warning above about the secure
world still stands.

## Two autofocus experiments held back for want of evidence

Both were sitting uncommitted in the working tree on 2026-08-15 with no recorded
rationale, and both were reverted so that r13 changed exactly one thing (the
manual-focus clamp). Neither has ever been built or measured. If either is picked
up it needs its own leg, not a ride on someone else's:

* **`kCoarseSteps` 12 → 9 and `kFineSteps` 7 → 6.** A scan is currently 19
  measurements, ~3.5 s at 1920×1080; this would make it 15. The question is
  whether the settled position stays within a step or two of the 385-394 band
  that [`camera/README.md`](camera/README.md) records for a lit indoor scene —
  same scene, same light, both builds, several scans each.
* **`interpolatePeak()` → `bestPosition_`**, i.e. dropping the parabolic peak
  fit. ☠️ This looks like a leftover from bisecting the out-of-bounds crash,
  which was localised and fixed in `059c6de`, so it probably has no reason left
  to exist. It argues against [the recorded rationale for taking the fit from the
  Raspberry Pi algorithm](camera/bringup/README.md#what-a-shipped-autofocus-does-differently),
  and against the other experiment as well: with **fewer** steps the answer is
  quantised more coarsely, so interpolation matters more, not less. Restore it
  only on a measurement showing the fit lands worse than the raw best sample.

## Untested: interconnect path for the SCM/crypto node

An idea from the SLIMbus framer investigation that was never confirmed:
downstream's `pil-tz` votes MASTER_SPS→EBI bandwidth around the PAS SCM calls,
while mainline's `qcom_scm_bw_enable()` is a no-op here because the `scm` node
carries no interconnect path. Adding one would make `bw_enable()` vote during
`pas_init_image` / `mem_setup` / `auth_and_reset`:

```dts
&scm {
	interconnects = <&pcnoc MAS_CRYPTO RPM_ALWAYS_TAG
			 &bimc SLV_EBI RPM_ALWAYS_TAG>;
	interconnect-names = "crypto-ddr";
};
```

The audio path works without it, so this is not a blocker — it is kept in case
ADSP boot timing ever needs revisiting.

## Also open, written up elsewhere

* **Charging asks for 2 A**, where it used to be capped at 1 A, and the battery
  it asks on behalf of is now verified before its limits are applied. What is
  left, in order: the **mismatch path has never run on hardware** (a
  device-tree-only cycle with a deliberately wrong `id-resistor-ohms` would
  measure it), **2 A has not been seen flowing** (needs a wall charger and a low
  state of charge), and the **input side** — without high-voltage negotiation the
  USB port supplies about 1.9 A into the cell. Still open beyond that: selection
  between the two packs the FP3 ships, which needs a binding for more than one
  `monitored-battery`; the float-voltage half of JEITA; step charging; and the
  thermal trip temperatures, which are a choice rather than a measurement. See
  [`charger/README.md`](charger/README.md).
* **Only the discharge half of the two-OS comparison is matched.** The idle
  discharges were run against each other deliberately; the charges were not.
  Ubuntu Touch charged from a wall charger, and both pmOS captures came off an
  SDP port at `usb_imax_uA 500000` — about 340 mA into the pack — so they show
  *that* charging terminates, not how it compares. A like-for-like charge needs
  the same charger and the same starting state of charge on both sides, and it
  pairs naturally with the two hardware measurements above, since all three want
  a wall charger and a low battery.

  ☠️ **The two halves age differently.** A charge measurement stays valid across
  the idle-current work; a discharge measurement does not, because the floor it
  rests on is the thing being changed. Re-running the matched discharge before
  the `ak7375` fix lands is work thrown away.
* **Sensors work**, including proximity blanking during a call and ambient
  light. What is left there is calibration rather than bring-up: the
  magnetometer has an unknown hard-iron offset and scale, and the mount matrix
  is inherited from msm8996. See [`sensors/README.md`](sensors/README.md).
* ~~**Camera streaming is not working end to end.**~~ **Stale — it streams.**
  `VIDIOC_STREAMON` succeeds and frames arrive at the full
  `SRGGB10_1X10/4032x3024`, 15 240 960 bytes each, which is exactly
  4032 × 3024 × 10 / 8: packed 10-bit, no padding, no short frames. See
  [`camera/README.md`](camera/README.md). The lead that remains from the original
  entry is narrower than it was: the driver's two modes carry link frequencies
  that disagree with the device tree's `link-frequencies`, and one is commented
  `// NOT SURE HOW TO FIND THIS VALUE` by its author — worth resolving before the
  series is sent, but it is not what blocks streaming, because nothing does.

## The package moved to `debug-int/7.1.3`

`linux-fp3/APKBUILD` pinned `_commit=c8974511d585` through two rewrites and ended
up unreachable from any branch: the camera-provenance rebuild on 2026-07-30 moved
it onto an archived lineage, and the debug split later the same day added a second
one. It was also, concretely, a kernel **without the watchdog** — the safety net
commit landed after it.

So on 2026-07-30 the pin moved to `debug-int/7.1.3` and `pkgrel` went to 23. That
is the branch the package builds from now on: `integration/<base>` plus the debug
layer, so what runs on the phone always carries the watchdog started at probe.
`integration/<base>` deliberately does not, because it is the branch that has to
keep matching the `submit` series.

The build and the deploy followed, and have been repeated many times since, so
the kernel the phone runs is built from that branch and carries the watchdog.

What is worth keeping an eye on is that the package and the device stay in
step. Between a hurried fix and the next bump the phone can end up running
hand-copied modules and a hand-copied DTB on top of an older package - a state
where `uname -v` and `apk info` disagree, and where any `apk` operation on
`linux-fp3` silently reverts the DTB through the mkinitfs trigger. The check
that catches it is `tests/fp3-selftest --only identity,modules,dtb`, which
compares the build stamp, the installed package, the source commit, the module
tree and the booted DTB against each other rather than trusting any one of them.

Both old tips are kept alive as tags —
`archive/integration-7.1.3-pre-camera-provenance` and
`archive/integration-7.1.3-pre-debug-split` — because GitHub serves a source
tarball only while its commit is reachable from some ref. Rewriting `integration`
without them would have left the pinned package un-buildable, a failure that
shows up much later than the change that caused it. The one-line check is in
[the branch model](../README.md#the-branch-model).

## AfWindows cannot reach the camera through PipeWire

> **✅ Layers 1 and 2 are done and measured (2026-08-16).** A focus window now
> travels from `pw-cli` to the metering: `libcamera` r18 offers the control in
> the sensor's active pixel array and aims at it, and `pipewire` r6 carries it
> across the node. Only layer 3 is left — the application still sends nothing.
> Both layers are held by checks proved in both directions:
> `44-camera-af-windows` (libcamera r17 fails, r18 passes) and
> `45-camera-af-windows-pipewire` (pipewire r5 fails, r6 passes).
>
> Measured end to end with a stream open, reading the IPA's own line:
>
> ```
> AfMetering=Windows alone -> Metering 9 of 25 zones (0 windows) [the centre fallback]
> [0, 0, 400, 300]         -> Metering 1 of 25 zones
> [3600, 2700, 400, 300]   -> Metering 1 of 25 zones
> [0, 0, 4032, 3024]       -> Metering 25 of 25 zones
> ```
>
> ☠️ **The claim below that no PropInfo in 1.6.8 publishes `container` together
> with a range is wrong.** `SPA_PROP_channelVolumes` does exactly that —
> `spa/plugins/audioconvert/audioconvert.c:582-584`, a `CHOICE_RANGE_Float`
> followed by `SPA_PROP_INFO_container, SPA_POD_Id(SPA_TYPE_Array)`. The pattern
> was established; the grep that concluded otherwise was too narrow.
>
> ☠️ **And a fourth gate that only the device showed: `pw-cli` does not send an
> array as a POD array — it sends a struct.** `spa_json_to_pod_part()`
> (`spa/utils/json-pod.h:68`) has only the static type table to work from, every
> camera control is published past `SPA_PROP_START_CUSTOM` and so appears in no
> table, and with no type a JSON array becomes a struct of ints. The very first
> `set-param` printed it:
>
> ```
> Struct: size 64
>   Int 0 / Int 0 / Int 100 / Int 100
> ```
>
> A plugin accepting only POD arrays would have published a control that cannot
> be set — indistinguishable, from outside, from not publishing it. Both shapes
> are accepted.
>
> **☠️ Update 2026-08-16: the chain breaks in three places, not one.** The
> PipeWire gate below is real and still has to be opened, but opening it alone
> changes nothing. Measured with `cam -c1 --list-controls` on the device:
>
> ```
> Control: [inout] libcamera::AfWindows: [(0, 0)/0x0..(0, 0)/0x0]
>    Size: n
> Control: [inout] libcamera::AfMetering:
>   - AfMeteringAuto (0) [default]
>   - AfMeteringWindows (1)
> ```
>
> `AfWindows` **is** advertised, and so is `AfMeteringWindows` — but the
> control's own bounds are **both the empty rectangle**. That is the same shape
> as the `LensPosition` defect that took two rounds to find: a control offered
> with a degenerate range, where every request clamps to nothing. So the work is
> layered, and the order matters because each layer is untestable until the one
> below it carries a value:
>
> 1. **libcamera / the soft IPA** — ✅ **done 2026-08-16**, patch `0106`
>    (`libcamera` r15). See the correction below: the algorithm already metered
>    arbitrary windows, so the work was narrower and in different places than
>    this line assumed.
> 2. **PipeWire** — ✅ **done 2026-08-16**, patch `spa-libcamera-array-controls`
>    (`pipewire` r6). The three `isArray()` gates below, plus the struct shape
>    `pw-cli` actually sends.
> 3. **aperture / Snapshot** — send a rectangle array rather than a scalar.
>    **The only layer left.**
>
> #### ☠️ Correction, 2026-08-16: layer 1 was not what it looked like
>
> "Make the AF algorithm honour the windows instead of falling back to
> `selectCentre()`" was **wrong** — `Af::selectZones()` has metered an arbitrary
> set of windows since the autofocus went in, and `queueRequest()` already
> called it. Reading the source before writing any of it turned one guessed
> defect into three measured ones:
>
> * **the degenerate `ControlInfo` is real**, and its cause is a comment that
>   promised something the plumbing cannot do: *"the bounds are filled in at
>   `configure()` time"*. They never were, and they never could have been — the
>   `ControlInfoMap` a camera advertises is taken **once**, when `SoftwareIsp`
>   constructs the IPA (`software_isp.cpp`, `ipa_->init(…, ipaControls, …)`),
>   and is never read again. `context_.sensorInfo = sensorInfo` happens in
>   `IPASoftSimple::init()` *before* `createAlgorithms()`, so `Af::init()` is
>   where the size is both available and effective.
> * **`AfWindows` was applied under `AfMeteringAuto` too**, contrary to the
>   control's own documentation (*"used by the AF algorithm when AfMetering is
>   set to AfMeteringWindows"*), and the reverse order was worse: switching to
>   `AfMeteringWindows` **after** windows had been given did nothing at all,
>   because the old `windowsSet_` flag made that branch a no-op and the zones
>   stayed on the whole frame. Both controls are now kept as requested and the
>   zones derived from the pair, so the result no longer depends on arrival
>   order.
> * **`selectZones()` silently metered the whole frame** when no window
>   survived clipping — the one thing a caller asking for windowed metering did
>   not ask for. It now reports whether it selected anything, and windowed
>   metering with no usable window falls back to the centre.
>
> ☠️ **The coordinate space is a deviation, stated rather than hidden.**
> `AfWindows` is documented as being in `ScalerCropMaximum` pixels; the simple
> pipeline handler publishes no such property (`git grep ScalerCropMaximum` hits
> only `rpi` and `rkisp1`), so there is nothing there for an application to
> read. The IPA measures against the sensor's **active pixel array**, and the
> control's own maximum states that space, which is machine-readable and — on a
> pipeline that cannot crop — is the same rectangle `ScalerCropMaximum` would
> name.
>
> ##### ☠️☠️ A fourth defect, found only by measuring end to end (`r17`)
>
> Two things the source review could not have found, both caught the first time
> a window ever reached the code:
>
> * **A single window aborts the IPA process.** `cam` — and anything built on
>   `ControlValue::set(Rectangle)` — holds one window as a **scalar**, not as a
>   one-element array, and reading a scalar through the array accessor asserts:
>   `Assertion failed: isArray_ (controls.h: get: 204)`. Fixed by reading the
>   raw `ControlValue` and accepting both shapes. Nothing had ever hit it
>   because no window could reach this code before.
> * **The coordinate space follows leftover driver state.** Measured two-sided:
>
>   ```
>   after a 1920x1080 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/1920x1080]
>   after a 4032x3024 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   ```
>
>   `context.sensorInfo` is taken **once**, in `IPASoftSimple::init()`, from
>   `sensor->sensorInfo()` — which reports the sensor's *currently applied* V4L2
>   format. That format persists in the driver between processes, so the space
>   an application is told to compute in is decided by whoever used the camera
>   last. `selectZones()` clips against the same member and has had this
>   dependency since it was written; the new `ControlInfo` did not introduce it,
>   it made it visible. The symptom that exposed it: a window at
>   `(3000, 2200, 400, 300)` selected 9 of 25 zones — the centre fallback —
>   because it lay wholly outside a 1920x1080 clip, while `(1900, 1050, 20, 20)`
>   selected 1.
>
>   **Fixed in `r18`** by using the sensor's *active pixel array*, which is a
>   fixed hardware property and does not move — `PixelArrayActiveAreas =
>   [ (8, 24)/4032x3024 ]` read identically after a 1080p capture and after a
>   full-res one. `IPACameraSensorInfo::activeAreaSize` carries it, so the
>   stale init-time snapshot is no longer a problem: the one field that moves is
>   the one that is no longer read. `selectZones()` maps a window onto the zones
>   proportionally and needs no absolute size of its own.
>
>   Measured after the fix — the space no longer follows what the last user of
>   the camera left in the driver:
>
>   ```
>   after a 1920x1080 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   after a 4032x3024 capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   after a  640x480  capture:  AfWindows: [(0, 0)/1x1..(0, 0)/4032x3024]
>   ```
>
>   and the two windows that used to fall back to the centre now aim:
>
>   ```
>   [0, 0, 4032, 3024]     -> Metering 25 of 25 zones      (was 25)
>   [2000, 1500, 400, 300] -> Metering  1 of 25 zones      (was 9 — centre fallback)
>   [3900, 2900, 100, 100] -> Metering  1 of 25 zones      (was 9 — centre fallback)
>   [0, 0, 100, 100]       -> Metering  1 of 25 zones      (was 1)
>   ```
>
>   ☠️ The mapping assumes the stream covers the active area. A sensor mode that
>   cropped rather than scaled would need `analogCrop` — which is known only for
>   the format the IPA was initialised with, and is therefore no more dependable
>   here than the output size was. Stated in the code and the commit rather than
>   silently assumed.
>
>   ☠️ `cam` cannot set a control from the command line — `-s` is stream
>   configuration. Controls go through `--script`, and that is how the scalar
>   shape above arrives:
>
>   ```sh
>   printf 'frames:\n  - 0:\n      AfMetering: 1\n      AfWindows: [ 0, 0, 100, 100 ]\n' > /tmp/af.yaml
>   LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO cam -c1 -C4 --script /tmp/af.yaml
>   ```
>
> The working half is measured too — windows do aim, once they land inside the
> clip: `[0,0,4032,3024]` → 25 of 25 zones, `[0,0,100,100]` → 1,
> `[1900,1050,20,20]` → 1. The `Metering N of M zones` line that makes any of
> this visible is part of `0106`; without it a window that reached nothing looks
> exactly like one that was never sent.
>
> Found on the way and fixed in `0102`: `toMicroseconds()` shadowed `exposure`,
> which a host build with `-Werror -Wshadow` rejects. The device build does not
> use those flags, so the defect had shipped. **Build a userspace patch on the
> host before packaging it** — it is minutes, and it is a different compiler
> invocation from the one the aport uses.
>
> One design point from yesterday is now confirmed rather than assumed: there is
> **no `SPA_TYPE_Region` POD type**. `struct spa_region` exists in
> `spa/include/spa/utils/defs.h` and is exactly libcamera's `{x, y, w, h}`, but
> it is a plain C struct with no entry in the `enum` in `spa/utils/type.h` and no
> builder or parser helper, so it cannot be put in a pod. Flattening to four
> `int32`s stands.

Tap-to-focus points at nothing. The tapped position never reaches libcamera,
because PipeWire's libcamera plugin maps only `bool`, `int32` and `float`
controls to node properties and returns early for arrays — and `AfWindows` is
an array of rectangles. Measured 2026-08-15 by dumping what the camera node
publishes:

```sh
pw-dump | python3 -c 'import json,sys
for o in json.load(sys.stdin):
    for pr in o.get("info",{}).get("params",{}).get("PropInfo",[]):
        i = pr.get("id")
        if isinstance(i, str) and i.startswith("id-01"):
            print(i, pr.get("description"), pr.get("type"))'
```

Only `AfMode`, `AfMetering`, `AfTrigger` and `LensPosition` come back. The
stand-in that shipped is `AfMeteringWindows` meaning *the centre 3×3 of the
5×5 zones*, defined in the IPA, which removes the dilution but cannot aim.

### Read in the source 2026-08-16: three gates, not one

PipeWire 1.6.8, `spa/plugins/libcamera/libcamera-source.cpp`. Three functions
each open with the same bail, so an array control is invisible as well as
unwritable:

| function | what it does | line |
|---|---|---|
| `control_details_to_pod` | publishes the PropInfo | `if (cid.isArray()) return nullptr;` |
| `control_value_to_pod` | publishes the current value | `if (cv.isArray()) return false;` |
| `control_value_from_pod` | accepts a written value | `if (cid.isArray()) return {};` |

and none of the three type switches has a `ControlTypeRectangle` case either.
`AfWindows` is `Span<const Rectangle>`, so it fails both tests. That is why the
control does not merely reject writes - it never appears in `pw-dump` at all.

**The shape of the fix is already in the tree, so do not invent one.** SPA
already carries array-valued properties: `SPA_PROP_channelVolumes` in
`spa/plugins/audioconvert/audioconvert.c:580` publishes a PropInfo whose `type`
describes *one element* and adds

```c
SPA_PROP_INFO_container, SPA_POD_Id(SPA_TYPE_Array));
```

to say the value is an array of them, with the value written by
`spa_pod_builder_array(b, sizeof(float), SPA_TYPE_Float, n, vals)`. Follow that:

- **PropInfo** - element range as `SPA_POD_CHOICE_RANGE_Int`, plus
  `SPA_PROP_INFO_container = SPA_TYPE_Array`.
- **value** - `spa_pod_builder_array(b, sizeof(int32_t), SPA_TYPE_Int, 4 * n, …)`,
  four ints per rectangle.
- **write** - read an Array of Int and regroup in fours.

☠️ **Do not use `SPA_TYPE_Rectangle`.** It exists, and it is the wrong type:
`spa_rectangle` is `{width, height}` only, with no origin, while libcamera's
`Rectangle` is `{x, y, width, height}`. A window without an origin cannot aim,
which is the entire point. Flattening to int32 is what keeps the origin.

Measured caveat, so the review is not a surprise: **no PropInfo anywhere in
PipeWire 1.6.8 publishes `container: Array` together with a range** - grep for
`SPA_PROP_INFO_type, SPA_POD_Array` returns nothing. `channelVolumes` is the
precedent for the *mechanism*, and it comes from an internal node rather than
from a device plugin's generic control loop. Expect to have to show that a
client which ignores `container` degrades sanely rather than misreading the
element range as the whole value.

Then the aperture control layer needs a way to write one; today it writes a
single number through `pw-cli set-param`. Note there is no local `pipewire`
aport - Alpine's lives in `community/pipewire` (`master` carries 1.6.8, matching
the device), so this needs a new `pmaports/temp/pipewire`.

## Does centre metering recover the focus signal?

**Not yet measured.** The A/B ran (2026-08-15) and proved only that the code
path works: the score falls to 0.385 of the whole-frame value, against 9/25 =
0.36 of the zones. Both legs were run on a bench scene with no focus peak in
it at all, so neither could show a peak and the comparison says nothing about
whether narrowing the zones recovers the modulation. Repeat it on the scene
that produced the 4.9 % figure — a phone held close over a keyboard, in room
light — with `AfMetering: 0` and `AfMetering: 1` alternating:

```sh
LIBCAMERA_LOG_LEVELS=IPASoftAf:INFO cam -c1 --capture=200 \
    -s width=640,height=480 --script=<script setting AfMode 1, AfMetering N, AfTrigger 0>
```

Only once that number exists is there anything to say about `min-contrast`,
which is 0.08 and was being missed by 3 percentage points.

## The tap moves the lens and nothing else

Three loops run on every frame and the tap reaches only the first:

| loop | what it sets | what it looks at | tap reaches it |
|---|---|---|---|
| AF | lens position | the centre 3×3 of the 5×5 zones | yes |
| AGC | exposure time + analogue gain | the whole frame | no |
| AWB | colour temperature | the whole frame | no |

Measured 2026-08-15 by photographing a lit monitor in a dim room: the letters
came out readable, so the lens went where the tap asked, while the centre of
the screen was blown out because the AGC had averaged the dark room in and
opened up. The camera node publishes no metering control for exposure at all —
`AnalogueGain`, `ExposureTime`, `ExposureTimeMode`, `AnalogueGainMode`,
`ColourTemperature` and `AwbEnable` are all scalars with no notion of *where*.

Two pieces, in this order:

1. carry rectangles through PipeWire (the section above). Nothing here can be
   aimed until a position can cross the socket, and the same fix is what makes
   `AfWindows` work, so it is one job serving both.
2. window the metering inside the IPA's AGC, modelled on the focus zones, and
   publish an `AeMetering`-style control next to `AfMetering` so the pipeline
   can ask for it.

## The shutter still fires mid-sweep in poor light

`FOCUS_SETTLE_MS` and `CAPTURE_FOCUS_SETTLE_MS` are 5500 ms, chosen against a
sweep measured at ~4.8 s. The sweep is not a constant: it is 19 positions plus
2 revisits, and the per-position cost is set by the frame rate, which the AGC
lengthens in poor light. Measured 2026-08-15: ~250 ms/position in room light
(~4.7 s) against ~570 ms/position in a dim room (12.7 s, 4:39:44 → 4:39:56).
So in poor light the capture still happens at an arbitrary lens position.

A longer timeout is the wrong fix — it would make every good-light shot slow.
The right one is for the IPA to say when the scan finished, which today it
does not: there is no completion control and `AfState` is not published. Until
then, note that lowering the position count (`kCoarseSteps` 12, `kFineSteps` 7)
shortens both cases proportionally.

## Deleting a photograph can take the viewfinder down

Undiagnosed. Symptom is a freeze in the gallery on delete, then "could not
play camera stream". The journal at 18:02:45 on 2026-08-15 shows the
**video** branch of camerabin starting without a filename and taking the whole
stream with it:

```
videobin-filesink: No file name specified for writing.
... Failed to start
pipewiresrc0: streaming stopped, reason not-negotiated (-4)
```

Why a delete should start the video branch is unknown, and guessing at it is
what to avoid — the next occurrence with a timestamp gives the full ordering
out of `journalctl --user -b`.

## The face-focus cascade is not archived here

`userspace-camera/snapshot/` now carries every patch the aport applies, but not
`facefinder` — the 234 KB binary cascade that `0020-camera-face-focus-mode`
loads at runtime. It lives only in `/mnt/1TB/pmos/pmaports/temp/snapshot`, an
upstream clone that is never pushed, so the aport still cannot be rebuilt from
this repo alone. Before copying it across, establish where it came from and
under what licence: a binary blob with no provenance is worse in a public
repository than a missing one, and the README has no row for it.

## Tap focus still hunts, and the obvious explanation is not the one

Reported 2026-08-16: with `focus-mode` set to `tap` the camera keeps focusing by
itself, which is what `continuous` is for.

Measured so far, and it rules more out than in:

- **The camera's own default is continuous.** `AfMode`'s PropInfo carries
  `Int 2` as its default, i.e. `AfModeContinuous`. So a mode that is never
  written does not leave the camera idle — it leaves it hunting, which is
  exactly the reported symptom. Anything that drops the write reproduces this.
- **`request_autofocus()` is all-or-nothing:** one missing control, or one that
  is not a labelled choice, and it returns without writing *any* of the pair -
  including the `AfMode` that matters. Since 0021 added `AfMetering` to every
  request, that looked like the answer.
- **It is not.** Both are published properly:
  `AfMetering` is an enum with labels `AfMeteringAuto`/`AfMeteringWindows`, and
  `AfMode` an enum with `AfModeManual`/`AfModeAuto`/`AfModeContinuous`. Every
  name and value `wanted()` asks for exists.

  ```sh
  pw-cli enum-params <camera-node> PropInfo   # as the session user
  ```

☠️ **The measurement that would settle it cannot be driven from a shell.**
Launching Snapshot over SSH as the session user starts the process but never
gets a viewfinder: no `org.freedesktop.portal.Camera` request appears in its
log, and `aperture` then logs "Camera never offered its focus controls; giving
up" — which is the app correctly reporting that no camera turned up, **not**
evidence about the focus path. Two runs were made this way before that was
noticed, and the lens sat at 872 through both because nothing was streaming.
The `giving up` line only means something in a session where `Capture at ...`
was logged first.

Next, in this order: drive the node directly with `pw-cli set-param <node> Props
'{ <AfMode id>: 1 }'` while the camera streams (the recipe is in
`tests/checks/45-camera-af-windows-pipewire-test.sh`) and watch
`v4l2-ctl -d /dev/v4l-subdev17 --get-ctrl focus_absolute` — a lens that keeps
moving with `AfModeAuto` set puts the fault below the app, one that settles puts
it in Snapshot.

## The whole desktop draws on the CPU, by distro policy

Measured 2026-08-16, and it is the answer to "is the camera using the GPU?" —
**no, and neither is anything else GTK4.**

`soc-qcom-msm8953-gpu` ships `/etc/profile.d/adreno-a506-quirks.sh`:

```sh
# Use the 'cairo' GTK renderer, so we prepare for the removal of
# the legacy GL renderer
export GSK_RENDERER=cairo
```

The reason given is portability, not a broken GPU — GTK is retiring its old GL
renderer and the distro is getting ahead of it. The cost is that every GTK4
application on the phone renders in software, the camera viewfinder included,
which is what a stuttering viewfinder looks like. phosh itself runs with
`GSK_RENDERER=cairo` in its environment, and every app it launches inherits it.

The GL renderer works here today: with `GSK_RENDERER=gl`, EGL gives an
**OpenGL ES 3.1 core** context on Mesa 26.1.6 / freedreno a506 under gtk4
4.22.4, with no fallback or error. The earlier measurement of what it is worth
was Snapshot at **130% CPU with cairo against 32% with gl**.

So `/etc/profile.d/zz-fp3-gsk-renderer.sh` now sets `GSK_RENDERER=gl`; it sorts
after the quirk, so it wins, and deleting it goes back. ☠️ **It only reaches the
session at the next login** — the running phosh keeps the environment it was
started with, so nothing changes until a re-login or a reboot.

☠️ The renderer name is `gl`, not `ngl`.

## Does the tap move anything but the focus?

Asked 2026-08-16, because the middle of the frame blows out after a tap. The
answer from the camera's own control list is **no, and it could not**:

```sh
pw-cli enum-params <camera-node> PropInfo | grep -E 'String "(Ae|Awb|Exposure|Analogue|Colour)'
```

Everything exposure-related the node publishes is a *global* control -
`ExposureTimeMode` (Auto/Manual), `ExposureTime`, `AnalogueGainMode`,
`AnalogueGain`, `AwbEnable`, `ColourTemperature`. There is **no** metering-window
or metering-mode control of any kind for exposure or white balance, so nothing
can be aimed at the tapped rectangle even in principle. And our patches write
none of them: the only "metering" anywhere in the series is `AfMetering`, which
is the focus one.

So the blown-out centre is not the tap following the frame — it is the
auto-exposure algorithm's own behaviour, and a separate question from the focus
work. Not yet measured.

**Confirmed 2026-08-25 one layer deeper, and the answer got worse.** The
reading above was taken off the *PipeWire node*, which leaves open that
libcamera has the control and PipeWire drops it. It does not. Read straight off
libcamera on the device:

```sh
cam -c 1 --list-controls
```

**Thirteen controls, and that is all of them:** `AfMetering`, `AfMode`,
`AfTrigger`, `AfWindows`, `AnalogueGain`, `AnalogueGainMode`, `AwbEnable`,
`ColourTemperature`, `Contrast`, `ExposureTime`, `ExposureTimeMode`, `Gamma`,
`LensPosition`. No AE or AWB region control of any kind. The soft ISP computes
**whole-frame** statistics; the only per-zone concept in the whole pipeline is
the autofocus one, and `AfWindows`/`AfMetering` are *our own* patch `0106`, not
upstream behaviour.

So there are three layers between a tap and a correctly-exposed subject, and
**the first one is already decisive**: the control does not exist; if it did it
could not cross PipeWire (the SPA plugin returns early for every array-typed
control); and the app has no concept of it either.

☠️ **The consequence is bigger than exposure, and it is the part worth
carrying:** since `AfWindows` is array-typed, *it* is one of the controls the
SPA plugin drops — so **on this phone the tap does not steer the autofocus
either.** A tap triggers a centre-metered scan, whatever the user aimed at. Two
separate entries in this file describe tap-focus behaviour as if the window
reached the sensor; both are describing centre metering. Cross-reference:
"AfWindows cannot reach the camera through PipeWire" above, which is the same
wall seen from the other side.


---

## The by-branch view — which branch owns what, and where it can be sent

*(Folded in from the former `FP3-TODO.md` on 2026-08-24 — one open-item list instead of two. Everything above is the by-item view; what follows maps each open item to its branch and its submission destination. Section and item numbers, including the `33f-*` labels other docs cite, are unchanged.)*

This is the **by-branch view** of what is still open: which branch owns which
item, and whether it can be sent anywhere at all. The by-item view above, with
the measurements and the reasoning behind each entry, is authoritative; this
view only says *what is open, on which branch, and where to read about it*. When
the two disagree, the by-item sections above win.

Until 2026-07-30 this by-branch view also shipped (as `FP3-TODO.md`) at the root of the kernel fork, on
`debug-int/<base>`. It was dropped there: the kernel tree carries kernel source,
and one file maintained in two repositories is one too many to keep honest.

The branch shape it describes:

```
integration/<base>   audio + voice + camera + charger + sensor
                     the pure cherry-pick sum of the upstream-bound categories,
                     so it stays a faithful mirror of what submit/* will carry
      |
      +-> debug-int/<base>   + the debug layer: one commit, the watchdog safety net
                             <- and this is the branch the linux-fp3 package builds
```

The package builds `debug-int/<base>` on purpose. The safety net has to be on the
phone — without the watchdog running from probe, a hang before userspace opens
`/dev/watchdog` leaves a device that has to be switched off by hand, and this one
is often not within arm's reach.

The branch layout itself (`wip/<base>/<category>` → `integration/<base>` →
`submit/<base>/<category>`, and the rule that a change must land on both its wip
branch and its integration) is defined in
[`fp3-pmaports/README.md`](https://github.com/llg179org/fp3-pmaports#the-branch-model);
the base-bump procedure is in
[`docs/rolling-a-new-base.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/rolling-a-new-base.md).

Hashes are deliberately absent except where a commit is being *cited* rather than
*tracked* — a head written into a file is wrong by the next push. Re-derive with:

```sh
git for-each-ref --format='%(refname:short) %(objectname:short=12)' \
  'refs/remotes/fork/wip/7.1.3/*' 'refs/remotes/fork/submit/7.1.3/*' \
  'refs/remotes/fork/integration/7.1.3' 'refs/remotes/fork/debug-int/7.1.3'
# note: there is no wip/<base>/debug - see "The `debug` layer" below
```

☠️ **The category list has grown past the five this file has sections for, and
the documented model has not caught up.** Measured 2026-08-24 against
`fork/7.1.3/main`, two more categories carry real commits:

| category | what it carries | why it is not one of the five |
|---|---|---|
| `power` | `wip/7.1.3/power` — 8 commits: the RPM sleep-set work (`regulator: qcom_smd` sleep-set votes plus the `both_sets`/`sleep_init` experiment knobs), `rpmsg: qcom_smd` wakeup-source and edge-interrupt-wake fixes, the APCS PLL-retune fix, and the SLIMbus `disable_stream` pair | it is the deep-sleep track, which started after the five were named |
| `i2c` | `submit/7.1.3/i2c` — the QUP runtime-PM pinctrl fix (the speaker-amp death) plus one adopted upstream cleanup | it began as a charger/audio symptom and ended as an i2c-core change |

Neither appears in the branch table in `~/.claude/CLAUDE.md` or in this file's
per-branch sections below. ★ **The test harness already knew about one of
them:** `tests/checks/CATEGORIES` lists six — `audio voice camera charger sensor
power` — and the runner enforces that every `wip/<base>/*` branch appears there.
So the harness and the prose disagree, and on `power` the harness is right.
`i2c` is in neither, which is consistent: it has a `submit/` branch but no `wip`
one. Treat the table there as **incomplete, not
authoritative**, until it is updated; re-derive the live list with the
`for-each-ref` above rather than from any prose list, including this one.

**And the category is decided by *why* the change is being made, not by which
directory it touches.** `drivers/slimbus/qcom-ngd-ctrl.c` is the worked example,
and it is split across two categories on purpose:

- `wip/7.1.3/audio` carries the QDSP6SS framer-bit commit and its revert — those
  were made to get the codec working.
- `wip/7.1.3/power` carries `implement disable_stream so the ADSP releases the
  channel` — the same file, chased because LPASS would not sleep.

So "a fix in `drivers/slimbus/` has no category" is **false**; ask what the
change is for.

---

## Where the work can go at all

Read this before spending effort on "upstreaming" anything. All of it is
AI-assisted, and that closes two of the three doors:

| destination | AI-assisted work | verdict |
|---|---|---|
| postmarketOS (pmaports, wiki) | banned outright | closed |
| msm8953-mainline (GitHub PR) | "we don't merge AI assisted work" — maintainer, [issue #197](https://github.com/msm8953-mainline/linux/issues/197), 2026-07-25 | closed |
| mainline Linux (LKML) | permitted **with disclosure** | the only path |

So `submit/7.1.3/*` targets the subsystem lists, never a pull request here.
Upstream-bound commits carry `Assisted-by: Claude:<model-id>` and the AI must
**never** carry a `Signed-off-by` — only a human can certify the DCO.

## Does it even apply to a maintainer tree?

Measured by cherry-picking each group onto a detached head at the real
destination, not inferred from "the files exist upstream". Re-measured
**2026-07-31** against fresh bases: Mark Brown `sound/for-next` `b8f7ea37085e`,
Sebastian Reichel `linux-power-supply/for-next` `c57cb36f76eb`,
`torvalds/master` `6269cc6f52c6`. **22 of 27 commits applied clean**, 23 after
one one-hunk resolution.

| group | destination | result |
|---|---|---|
| charger driver + binding | `psy/for-next` | 6/6 clean |
| charger dts | mainline | 2/2 clean |
| charger `adc5` channel | mainline | 1/1 clean |
| sensor (`qmi_encdec`) | mainline | 1/1 clean |
| camera dts | mainline | 1/1 clean |
| camera driver | mainline | one `Kconfig` hunk; the second commit is clean once resolved |
| audio driver + binding | `sound/for-next` | 11/12 — only the machine driver conflicts, on item 8 |
| audio dts | mainline | conflicts — `&sound_card` does not exist |
| voice | `sound/for-next` | the file does not exist upstream |

Audio moved from "conflicts on patch 1" to eleven of twelve, because the binding
was written and the series regenerated. The camera's `Kconfig` conflict moved
from the IMX355 entry to `VIDEO_OV9282`; it follows whichever entry sits next to
ours, so the neighbour's name is not worth tracking.

☠️ Counted per commit, aborting each failure before trying the next, so a group's
figure is "how many of these apply" and not "how far the series gets". Where a
failure cascades the two differ sharply: the camera import creates `imx363.c` and
fails on `Kconfig`, after which the delta commit has no file to patch and the
group reads 0/2 when the truth is one trivial hunk.

Redo this after every base bump; it is the only thing that answers the question.

---

## Before anything is submitted

Cross-cutting, mostly `dtbs_check` fallout. Detail:
[`docs/TODO.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/TODO.md).

7. **The camera driver's two-line `Kconfig` conflict** — the neighbouring IMX355
   entry gained a `select V4L2_CCI_I2C`. Trivial, but manual.
8. **The audio prerequisite is named and was posted:** Adam Skladowski,
   *MSM8953/MSM8976 ASoC support* v3, 8 patches, 2024-07-31, state `new`
   ([series 875540](https://patchwork.kernel.org/project/alsa-devel/list/?series=875540),
   cover `<20240731-msm8953-msm8976-asoc-v3-0-163f23c3a28d@gmail.com>`). We need
   1/8, 5/8 and 6/8: `qcom,msm8953-qdsp6-sndcard`, `msm8953_qdsp6_add_ops` and
   `use_ibit_clk` are all out-of-tree today, and so is the `&sound_card` label the
   DTS patch appends to. Declarable with `b4 prep --edit-deps`. Worth asking on
   alsa-devel whether it is still alive before building on it.
9. **Voice is not sendable as-is.** Prior art: Joel Selvaraj's
   `5a63debde2db` (2022-10-02, `sdm670-mainline/linux`) already contains the
   SLIMbus voice routing line for line, including the
   `{ "SLIMBUS_0_RX", NULL, "SLIMBUS_0_RX Voice Mixer" }` edge whose absence we
   booked as our own discovery — and it covers SLIMBUS_0 through 6, where we cover
   0. The `q6voice` driver was never posted to a list, so there is no message-id to
   cite and no upstream file to patch. The realistic move is to offer the
   SLIMBUS_0 work to that series' authors, not to send ours.
10. **Cover-letter disclosure** per `Documentation/process/generated-content.rst`:
    which tools, which prompts, which parts, and how it was tested.
## `wip/7.1.3/charger` — PMI632 SMB5

Fast charge, hardware JEITA, battery ID + thermistor, cooling device. All nine
commits of `submit/7.1.3/charger` apply clean, though to three different trees —
six to `psy/for-next`, two dts and one `adc5` channel to mainline. Gaps, in
[`docs/charger/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/charger/README.md#known-gaps):

155. **Check whether the series owes a `defconfig` patch.** Measured 2026-08-30:
    `CHARGER_QCOM_SMB2` is not in mainline's `arch/arm64/configs/defconfig` — but
    that symbol name is ours, and the upstream driver this work extends
    (`qcom_smbx`, serving pmi8998 / pm660 / pmi632) already exists, so the real
    question is whether *its* symbol is enabled there and whether adding the
    pmi632 compatible needs anything new. One command answers it against the
    driver's actual Kconfig symbol:
    `grep -E '^CONFIG_CHARGER_QCOM' arch/arm64/configs/defconfig`. If nothing is
    enabled, the charger cannot work on a stock kernel build and the series needs
    a defconfig patch; if the symbol is already there, it owes none. The audio
    series was checked the same way and owes none — `SND_SOC_WCD9335`,
    `SND_SOC_APQ8016_SBC` and `SLIM_QCOM_NGD_CTRL` are all already `=m`.

11. **No high-voltage negotiation on the input side** — the port settles near
    1.9 A, just under the programmed 2 A. This is the next real feature here, and
    a piece of work in its own right.
12. **2 A has never been seen flowing.** Needs a wall charger, a low state of
    charge and a USB meter. Physical.
13. **The mismatch path has never run on hardware.** A DTB-only cycle with a
    deliberately wrong `id-resistor-ohms = <50000>`; expected: the refusal message
    plus `0x1061` staying at `0x14`. Two DTB deploys, no kernel build, no flash.
14. **After a mismatch the previous boot's JEITA thresholds stay in the
    comparators**, not the PMIC defaults — a warm reboot does not reset the PMIC.
    The current limit is safe; the temperature limits are stale. Needs a
    characterised safe default.
15. **The DT can only describe one of the two packs** the FP3 ships (this one is
    Fuji). The ID is checked, so a wrong pack cannot be charged on the wrong
    limits — but it falls back to ~1 A, and the OCV curve is still read from the
    battery node even when the ID did not match. What is missing is the
    *selection*: a multi-`monitored-battery` binding mainline does not have.
16. **Half of the float-voltage story is untouched** — the `*_SL_FCV` bits are at
    their PMIC default; the scaling register is undocumented in every source
    available for this generation.
17. **Hardware JEITA gives one threshold per side; the downstream profile has five
    bands.** The 40–45 °C / 1500 mA step cannot be expressed. The full table would
    mean software JEITA — driven by the approximate temperature curve, which is
    the reason not to.
18. **The trip temperatures are a choice, not a measurement.** Nobody has charged
    this phone hard enough to find out which one it reaches.
19. **No step charging and no `auto-recharge-vbat-mv`** (downstream sets both,
    4300 mV). Worth adopting after the above.

## `wip/7.1.3/audio` — WCD9335 on SLIMbus

156. **★ The upstream blocker for the machine driver is now one small generic
    patch — measure the ADSP API version and write it.** Read in mainline
    `master` 2026-08-30: `q6core_get_svc_api_info()` is upstream and exported,
    handles both shapes of the ADSP service list, and `q6afe` already calls it at
    probe into `afe->ainfo`; a NULL-port param path exists too. The only piece
    missing is that `q6afe_port_set_sysclk()` dispatches **by clock id alone**, so
    `LPAIF_BIT_CLK` always takes the old `AFE_PARAM_ID_LPAIF_CLK_CONFIG` path even
    on firmware that wants `AFE_PARAM_ID_CLOCK_SET`. Making that switch consult
    `afe->ainfo` is the whole job, and it is generic across msm8909/8916/8917/
    8953/8976.
    **Verified against the destination tree 2026-08-30**: `q6afe.c` is
    byte-identical on `torvalds/master` and `broonie/sound.git for-next`, so the
    gap is real where the patch would land, not merely on a stale mirror — worth
    re-checking before sending, since this file is actively developed.
    **Step 1 is a measurement, on the device:** what `api_version` does this ADSP
    report for the AFE service? The condition turns on that number and nothing
    else. **Step 2 is the mail, not the patch:** Otto Pflüger's series
    (2023-10-29) and Adam Skladowski's (2024-07-31) are both formally alive, and
    the rule here is to reply on their threads rather than post a third one —
    especially since neither author could test on hardware and we can.
    If it lands, our own machine-driver patch loses its per-SoC hardcode
    entirely, and what remains of the dependency is the uncontroversial Quinary
    MI2S support plus the compatible and its binding.

Playback, microphone, MBHC and the call path all work on the device. Blocked
upstream on item 8. How it works is in
[`docs/audio/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/audio/README.md),
how it was arrived at in
[`docs/audio/bringup/`](https://github.com/llg179org/fp3-pmaports/tree/main/docs/audio/bringup);
the gaps are here and only here:

20. **The intermittent first-use failure needs a new lead, not another
    workaround.** The QDSP6SS framer-poke suspicion was closed by measurement
    (A/B, 8 cold boots each side, no difference) and the pokes were reverted; see
    [`docs/audio/bringup/qdsp6ss-framer-poke.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/audio/bringup/qdsp6ss-framer-poke.md).
21. **The `21`/`22` acoustic selftest checks fail** at −12 dB and at 0 dB while the
    speaker path itself measures clean (999.76 Hz at 31.77 dB). Unexplained, and
    deliberately not filed as environmental.
22. **A stray `Quinary MI2S` backend can attach to the voice front end.**
34. **A bare `BIT(2)` is written into `WCD9335_CODEC_RPM_CLK_MCLK_CFG`.** It
    wants a macro, but neither we nor downstream can name the field truthfully —
    so either a neutral name plus a comment, or an A/B that decides whether the
    write is needed at all. The commit's "garbled playback without it" is not
    backed by a recorded measurement.
35. **The `0x20` written into the EFUSE sense-state field is dead.**
    `SSTATE_MASK` is `GENMASK(4,1)` = `0x1e`, so the call only clears bits 4:1 —
    correct behaviour, misleading constant. Writing `0` is arithmetically
    identical, so no device time is needed. Inherited from downstream.

    ✅ **Confirmed by reading, 2026-08-26** — `wcd9335.h:27` is
    `GENMASK(4, 1)` and `wcd9335_enable_efuse_sensing()` passes `0x20`, so
    `0x20 & 0x1e == 0`. The fix is to pass `0` and to say "clear the sense-state
    field" in the comment rather than "select sense state 0", since `0x20` never
    selected anything. Ready to ride the next build; not deployed.
36. **`WCD9335_CODEC_RPM_CLK_MCLK_CFG_12P288MHZ` is `BIT(0)`**, same as
    `_9P6MHZ`; downstream writes `0x03,0x00` for 12.288 MHz.

    ☠️ **The words "unused" and "low priority" in the earlier version of this
    item were wrong, and reading the two trees on 2026-08-26 settled both
    halves.** The define *is* used — upstream's own
    `wcd9335_codec_set_sysclk()` selects between `_12P288MHZ` and `_9P6MHZ` on
    `wcd->mclk_rate` — so a board asking for 12.288 MHz is silently programmed
    to 9.6 MHz. What is true is that no *in-tree machine driver* ever asks:
    `apq8016_sbc.c` and `apq8096.c` both pass 9 600 000, which is why nothing
    has ever failed on it. So it is a live defect with no in-tree reproducer,
    not a dead constant, and it does not affect this phone.

    The correct value is **`0`**, and the vendor source names it twice
    independently: in `techpack/audio/asoc/codecs/wcd9335.c` both
    `tasha_codec_probe()` paths write `{0x03, 0x00}` for
    `TASHA_MCLK_CLK_12P288MHZ` and `{0x03, 0x01}` for `TASHA_MCLK_CLK_9P6MHZ`.
    A maintainer may still prefer deleting the define *and* the branch that
    uses it — that is a bigger call than the one-line correction, and it is the
    question to put in the patch, not to decide here. Standalone patch, own
    cycle.
37. **The `usleep_range(1000, 1100)` before the TX-hold release has no cited
    source** and runs per-ADC on every wcd9335 board. Removing it risks the
    silent capture returning, so it costs cold-boot A/B time. The same commit
    should say why the release is in the ADC widget's `POST_PMU` and not the
    decimator's.
38. **The reviewer asked for a table instead of the `switch`** in
    `wcd9335_get_dmic_clk_val()`. Cheap — but the `switch` deliberately mirrors
    mainline `wcd934x_get_dmic_clk_val()`, and converting wcd934x too means
    touching a driver we cannot test. Pick one, do not drift.
39. **The MBHC provenance needs reading, not patching.** MBHC really was in the
    2018 series (11/13 in v3, 11/14 in v4, dropped in v5, and v6 is what was
    accepted), but `254359e1` is superseded — item 23 replaced it with the shared
    `wcd-mbhc-v2`, whose legacy backend cites only its OnePlus downstream source.
    The question is whether anything there derives from the 2018 patch; citing it
    otherwise would be a false derivation claim.
40. **The TX-hold fix is codec-wide.** Mainline takes the hold and never releases
    it, so nothing can regress. By inspection of the device trees — not measured
    — OnePlus 3/3T are the only other wcd9335 board with analog mics wired, so
    they gain working analog capture; db820c and the Xiaomi msm8996 boards see no
    change. Belongs in the cover letter, with a Cc to maintainers who have the
    hardware.

41. **The WCD9335 does not survive an ADSP restart — diagnosed and fixed
    2026-08-23.** The SLIMbus NGD master is on the ADSP, so an ADSP SSR takes
    the codec's bus out from under it. The cause is not the bus going away, it
    is that `wcd9335_slim_status()` **ignored its `status` argument** and ran
    the whole bring-up on the *absent* notification, over a bus that was
    already down — leaking a register-map pair per restart and leaving the
    previous interrupt chip installed. Full account, with the before/after
    capture, in [`TODO.md`](TODO.md#-defect-3-diagnosed-the-codec-ran-its-bring-up-on-the-absent-notification).

    Three commits on this branch: `aba7e40c` (check the version-detect reads,
    which were testing uninitialised locals), `1d3ae998` (dispatch on the
    status and tear down on the way down; the irq chip and the ASoC component
    move off `devm` because their lifetime is the bus session, not the driver
    binding), `42b7e745` (free the per-function interrupts, which were `devm`
    on a device that never unbinds).

    **All three are upstream-shaped** — `wcd934x` already dispatches on the
    status, so this is wcd9335 catching up rather than an invention, and none
    of it touches anything out of tree. ☠️ `wcd934x` still has the sibling half
    of the same hole: it leaks its register map and re-adds its irq chip on a
    second present notification. Worth saying so in the cover letter; fixing it
    blind is not, since nobody here has that hardware.
    Proven to `#73-fp3` (r72); r73 carries commit three and is not yet
    deployed.
42. **`slim_rx_mux_put()` could NULL-deref from a mixer write** — fixed on this
    branch (`647cb5a1`) by initialising the channel list heads in
    `wcd9335_codec_probe()` instead of only in `wcd9335_set_channel_map()`.
    **Upstream-shaped and self-contained**; the bug is reachable by any user with
    access to the mixer on any wcd9335 board whose codec re-probes. Verified only
    as "did not crash in four attempts, one of them through the failure burst" —
    the crashing state was entered once, so the evidence is thin.
43. **`apq8016_sbc.c` latched the SLIMbus channel-map setup** for the life of the
    card, guarding state that lives in the codec — fixed here (`2f4ea47a`).
    ☠️ `sound/soc/qcom/sdm845.c` has the same shape and is untouched; deciding
    whether to fix both is part of preparing this one.

## `wip/7.1.3/camera` — Sony IMX363

Three commits: a verbatim import, our power-path delta, the DT node. The driver
is **Joel Selvaraj's** (`sdm670-mainline/linux` MR !3, commit `5130bc702ea2`,
2024-08-15), archived byte-identically on `vendor/imx363-sdm670`; our measured
delta is +68/−21 on 1514 lines, roughly half comments, functionally four things in
the power path.

154. **The series owes a `defconfig` patch, and does not have one.** Measured
    2026-08-30: `arch/arm64/configs/defconfig` in mainline `master` carries no
    symbol for this sensor — unsurprisingly, since the driver is not upstream at
    all. The canonical shape of a driver series is *binding → framework change →
    driver + Kconfig → **defconfig** → DTS*, and the defconfig patch is the piece
    most easily forgotten, because the developer's own build already has the
    symbol enabled and nothing local fails without it. Without it the sensor
    cannot work on a stock kernel build, which is most of the point of sending
    it. Settle the exact symbol name when the driver's Kconfig entry is written
    — ours is `VIDEO_IMX363` today, and that name is ours to propose, not a
    given. Check, do not assume: `grep -E '^CONFIG_<SYMBOL>=' arch/arm64/configs/defconfig`.
    (Source: Matt Porter, *Upstreaming 201*, Linaro Connect HKG15.)

33. **The focus actuator is at 0x0c and is not an LC898217.** ☠️ **This
    corrects the same item written earlier the same day.** `lc898217.c` plus its
    binding and MAINTAINERS entry landed 2026-08-01 and are worth keeping — the
    register map was read out of the board's vendor library
    `libactuator_lc898217xc.so` and validated against `libactuator_dw9714.so`,
    whose answer mainline's `dw9714.c` already states — but **the board DT node
    was removed again** (`wip/7.1.3/camera`), because it described hardware this
    phone does not have. Measured: with the actuator rail forced on and the
    sensor resumed so the camera IO rail is up, a **forced** scan of the CCI bus
    answers `0x0c 0x1a 0x50` and **nothing at 0x72**. ☠️ The scan must be forced
    (`I2C_SLAVE_FORCE`) or it silently skips every driver-claimed address —
    exactly the ones under investigation. Every `LC898*` in the vendor tree is at
    0x72 and every other family at 0x0c. ☠️ **Resolved later the same day, and
    the resolution is that both parts are real:** the vendor's
    `/vendor/etc/camera/camera_config.xml` pairs module `imx363` with
    `lc898217xc` and both second-source modules (`imx363_2nd`, `imx363pv_2nd`)
    with **`ak7374`** — Fairphone ships this phone two ways, exactly as it does
    with the battery pack. This phone has a second-source module, so `ak7374` it
    is; `dw9800` was never a candidate here, it belongs to a different module in
    the same file. Support is a chipdef plus a compatible in mainline's existing
    `ak7375.c` (register 0x00, 10 bits, shift 6, no standby), with the board node
    restored to point at it. The decode was re-validated against **two** known
    answers, `dw9714` and `ak7345`, after a four-byte base-offset error made
    every field decode to a plausible wrong value — see item 33b. ☠️ The
    downstream `value = 1023 - position` inversion excludes exactly `ak7374` and
    `dw9800`, so the polarity argument built on it does not apply to this board.
    Two side findings, both of
    which had looked like driver bugs: **the CCI bus does not work until the
    sensor's IO rail is up** (timeout `-110` versus `-ENXIO` tells "bus dead"
    from "nobody home"), and **a failed runtime-PM resume latches** into
    `runtime_status: error`, after which every resume returns `-EINVAL` and the
    subdev open fails several steps away from the real error — unbind/rebind
    clears it. Detail in
    [`docs/camera/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/camera/README.md#the-focus-actuator).
33a. **`lens-focus` is how a lens subdev joins the graph**, and it worked:
    `v4l2_async_register_subdev()` alone leaves the subdev unclaimed, with no
    devnode and no media entity, so the driver is bound and invisible at once.
    `imx363` registers via `v4l2_async_register_subdev_sensor()`, which parses
    `lens-focus`; adding the reference put the lens in the graph immediately. The
    `lens-focus: true` line stays in `sony,imx363.yaml` for whatever part turns
    out to be fitted.
33b. **A vendor-blob decode is only worth what its known-answer control is
    worth.** The actuator parameter structure starts at `.data + 0x04`, not at
    `.data`, and with that four-byte error every field still decoded to a
    plausible value — an I²C address, a bit width, a register number, none of
    them right. Nothing in the output looked wrong. What caught it was running
    the identical decode against parts mainline already documents: `dw9714`
    (0x0c, 10 bits, no register address, shift 4) and `ak7345` (0x0c, 9 bits,
    register 0x00, shift 7). Seven fields across two parts now agree, and the
    AK7374's own numbers satisfy the family invariant that position width plus
    shift fills a 16-bit word (9+7, 10+6, 12+4). **Do not accept a struct decode
    without at least one control whose answer is known independently**, and
    prefer two — the first control is what made the earlier LC898217 decode
    trustworthy, and it is what made this one repairable.
33c. ✅ **SETTLED: the lens moves, and the two earlier verdicts were both wrong -
    in opposite directions - for reasons of measurement design.** Measured
    2026-08-01 on `linux-fp3-7.1.3-r32` (`#33-fp3`) with one capture held open
    for the whole run and the positions visited in interleaved passes of
    alternating direction. Full range, 11 positions x 3 passes: a single interior
    peak at 409 (428.7) with flat tails (0 -> 387.3, 1023 -> 380.6), between
    positions 48.1 against a worst within-position spread of 3.4, and only 1.3 of
    pass-to-pass drift. Zoomed in, 280..480 in 9 steps x 4 passes: peak at **380**
    (437.6), between 43.4, within 3.5, drift 0.9 - and 380 is where the operator
    independently reported the viewfinder looking sharp. ☠️ The two failure modes,
    both worth carrying: (1) the first "it moves" confounded position with capture
    order (0 always first, 1023 always second; order-balancing collapsed 44.0 to
    0.93 against a 0.76 order effect); (2) the "it does not move" restarted the
    stream for every capture - resetting auto-exposure and injecting a transient
    as large as the signal - **and compared 0 against 1023, the pair with the
    least contrast available**: they differ by 6.7 while the peak stands 48 above
    both. The response to this control is a peak, not a ramp, so an
    extremes-vs-extremes test is structurally blind to it. **Choose the contrast
    pair from the shape of the expected response, not from the ends of the input
    range.**
33c-1. **What is eliminated, all measured.** Writes reach the part (no i2c
    error); it is powered (`cam_af_2p85` and `cam_io_1p8` enabled, TLMM 128 and
    130 read `out high`); runtime PM keeps it `active`; the active-mode write
    happens (`ak7375_vcm_resume()` writes `reg_cont = mode_active`
    unconditionally - `has_standby` gates only the suspend-side write, which an
    earlier note here got wrong); nothing else writes the control (a value set
    with the camera app running is unchanged three seconds later, three times,
    and there is no autofocus on this stack); and the vendor does nothing more -
    its parameter block is fully decoded, ten register descriptors of which only
    the first is filled plus a single init write of `0x02 = 0x00`, which is
    exactly what the driver does.
33c-2. **What is still open on the actuator**: the *direction* (no position has
    yet been related to a subject distance - two targets at known distances and
    one sweep each settle it), and the *name* (that it is an AK7374 is inferred
    from the absence of anything at 0x72 plus the vendor configuration, not from
    asking the device; the sweep raises the confidence a long way, since a wrong
    register map would not produce a clean focus curve, but the module EEPROM at
    0x50 is where an identifier would actually be read - its layout is in
    `libmmcamera_ofilm_imx363_bl24s64_eeprom.so`, decodable the same way the
    actuator parameters were).
33d. **The recorded capture command did not work from a cold boot**, and the
    failure looked like a driver bug. The CAMSS pads default to
    `UYVY8_1X16/1920x1080` while the sensor is at `SRGGB10_1X10/4032x3024`, so
    `STREAMON` fails `-EPIPE` from pipeline validation with nothing in dmesg —
    the same symptom the pixel-format trap produces, from a different cause. The
    fix is to propagate the sensor format down `msm_csiphy0`, `msm_csid0`,
    `msm_ispif0`, `msm_vfe0_rdi0` with `media-ctl -V` first. Now done by
    `focus-sweep.py` itself and written into
    [`docs/camera/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/camera/README.md).

33e. **SETTLED 2026-08-01 - autofocus is written and works.** libcamera's
    `simple` pipeline handler had no autofocus at all: `ipa_soft_simple.so`
    contained no focus symbol, the tuning file listed only
    `BlackLevel`/`Awb`/`Adjust`/`Agc`, and an app saw `Contrast` and `Gamma` and
    nothing else. It now carries a contrast-detection AF, kept as
    [`userspace-camera/libcamera/0101-simple-autofocus.patch`](https://github.com/llg179org/fp3-pmaports/blob/main/userspace-camera/libcamera/):
    a sharpness statistic in the software ISP's existing stats pass, accumulated
    into a 5x5 grid of zones; an `Af` algorithm in the simple IPA doing a coarse
    ladder of twelve positions then a fine ladder of seven; and the lens plumbed
    through the way the IPU3 handler does it. `AfMode`, `AfTrigger`, `AfMetering`
    and `AfWindows` are published. Verified live: a scan settles on **372**
    against the **380** that `focus-sweep.py` measures independently, and takes
    about 3.5 s at 1920x1080 (14 s at 4032x3024, because statistics come once
    every four frames and the software ISP sustains only ~6 fps there). Still
    open underneath it: the metric is not a proper contrast measure of a
    band-limited image, the search does not interpolate between the two best fine
    positions, and `LensPosition` is deliberately **not** advertised because it
    is defined in dioptres and no lens position on this phone has been related to
    a subject distance (see 33c-2). Whether the patch is worth offering upstream
    is a separate question - it is written to their conventions and carries
    `Assisted-by:`, but it has been measured on exactly one sensor.
33f. **Unbinding the ak7375 driver leaves a dangling ancillary media link and
    warns in the regulator core.** Each unbind/rebind adds another
    sensor-to-lens ancillary link instead of replacing it, and one of them ends
    up with a sink id of 0; libcamera then rejects the entire media device with
    `Failed to find MediaObject with id 0`, so the camera vanishes from every
    app until a reboot - while the actuator still works perfectly through V4L2.
    The unbind also produces `WARNING: drivers/regulator/core.c:2657 at
    _regulator_put` from `devm_regulator_bulk_release`, i.e. the supplies are
    still enabled when the driver is released. Both look like upstream bugs
    rather than integration mistakes, but neither has been reduced to a minimal
    reproducer yet, and neither is on any path the phone takes in normal use.
33f-2. **Merely enumerating the cameras can wedge the focus lens until reboot**,
    and this one *is* on a path normal use takes. Opening the lens subdevice
    runtime-resumes the actuator over the CCI bus; do that while another client
    is tearing the camera down and the transfer times out
    (`i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout`, then
    `ak7375 0-000c: ak7375_vcm_resume I2C failure: -110`). Runtime PM latches the
    failure, so every later open returns `EINVAL`, libcamera logs *"Lens
    initialisation failed, lens disabled"*, and autofocus disappears for the rest
    of the boot while the camera still streams. Reproduced 2026-08-01 by
    restarting the PipeWire stack on top of a running camera client; **not**
    reproducible sequentially - two clean boots, four camera creations each,
    including one after a streaming run, all fine, and a PipeWire restart with
    nothing else touching the camera is also fine. Unclear yet whether the fault
    is the CCI driver's arbitration, the actuator's resume ordering, or a shared
    regulator dropping mid-transfer; each is a separate measurement.

    ☠️ **It does not take two *clients*, and libcamera's exclusivity does not
    protect against it.** Read in the source 2026-08-02:
    `CameraSensorLegacy::init()` calls `discoverAncillaryDevices()`, which opens
    the lens subdevice — at **camera creation**, so during plain enumeration,
    long before `acquire()` and entirely outside its lock. Measured the same
    day: `cam` was refused the camera with *"Pipeline handler in use by another
    process"* and had **still** powered the VCM up over I²C by then. The rule
    "one client at a time" is therefore not enough; anything that merely lists
    cameras touches the hardware.

    That also points at a fix: open the lens lazily, on `acquire()`, the way the
    uvcvideo pipeline handler already delays opening `/dev/video#` for power
    reasons. It would put the lens inside the exclusivity that already exists
    rather than inventing new arbitration.
33f-3. **The same CCI timeout can take the whole phone down, not just the
    lens.** Measured 2026-08-23 on r73 during a `fp3-selftest` battery: a
    `i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout` was followed 2 ms later
    by `imx363 0-001a: Error reading reg 0x0016: -110`, then 60 s later
    `qcom-camss 1b00020.camss: VFE halt timeout`, then **60** `qcom-iommu-ctx
    1e34000/1e35000.iommu-ctx: timeout waiting for TLB SYNC` at 5 s intervals
    over 518 s, and finally `watchdog0: pretimeout event` — the debug layer
    resetting a phone that could not tear the camera down. Capture:
    [`docs/power/bringup/captures/2026-08-23_camss-iommu-wedge-watchdog.txt`](power/bringup/captures/).
    ☠️ **Do not assume 33f-2's fix covers this.** 33f-2's `-110` is on the
    **ak7375 lens**, and its proposed remedy is to open the lens lazily on
    `acquire()`. This `-110` is on the **imx363 sensor**, on a register read, so
    a lazy *lens* open would not obviously prevent it. What the two share is the
    shape — a CCI transfer colliding with a camera teardown — not the victim.
    Reproduced twice at battery scale (2 of 2 runs that include the camera
    block); a battery with `--skip camera` completed without a reset, and one
    with the first half of the pre-camera checks dropped still reset. Not yet
    reduced to a minimal reproducer, and not yet known whether the sensor `-110`
    causes the VFE halt timeout or both are downstream of the same stuck bus.
    ☠️ Two earlier resets in the same investigation were RCU stalls in
    `cpuidle_enter_state` with **no** camss or IOMMU line at all; that boot had
    zero RCU stalls. Two failure modes, one watchdog — do not merge them until
    something links them.

33f-4. ★ **The CCI timeout also happens at boot, before anything touches the
    camera.** Observed 2026-08-23 on a deliberately fresh boot of r73, 13 s in:

    ```
    [ 12.958088] qcom,apr remoteproc1:...apr_audio_svc...: Adding APR/GPR dev: aprsvc:service:4:b
    [ 13.159624] i2c-qcom-cci 1b0c000.cci: master 0 queue 0 timeout
    [ 13.160110] imx363 0-001a: Error reading reg 0x0016: -110
    [ 13.169992] remoteproc remoteproc2: remote processor a204000.remoteproc is now up
    ```

    So the sensor's first register read fails, at probe, wedged between the APR
    audio service registering and the second remoteproc finishing its
    bring-up — with no camera client in existence. That matters for 33f-2 and
    33f-3, both of which explain the same timeout by a *client* colliding with a
    teardown: here there is no client and no teardown. Whatever arbitration is
    missing on this bus is missing at probe too.
    ☠️ **One observation, not a rate.** It has been seen on exactly one boot so
    far, because the phone retains only two boots of journal (see the rootfs
    item in [`STATUS.md`](STATUS.md)) and the earlier ones are gone. Confirm the
    rate with `docs/power/bringup/tools/kmsg-tap.sh`, which keeps the log on the
    host across reboots, before treating it as deterministic.

33g. **Focusing on demand works; focusing on a *point* still stops in
    PipeWire.** The zones and the `AfMetering`/`AfWindows` controls a tapped
    point needs are implemented in the IPA, but PipeWire's libcamera plugin maps
    a control to a node property only for `bool`, `int32` and `float` and
    returns early for any array (`if (cid.isArray()) return nullptr;` in
    `spa/plugins/libcamera/libcamera-source.cpp`, read from the source
    2026-08-01), so `AfWindows` never leaves libcamera. `AfMode` and `AfTrigger`
    do, which is enough for "focus now" and is what the app uses: Snapshot's
    autofocus switch and its tap-to-focus bind the PipeWire node directly - the
    `GstDevice` carries the id in `object.id` - because `pipewiresrc` has no
    properties for camera controls either. Verified by hand before any code was
    written: `pw-cli set-param <node> Props '{ 16777249: 1 }'` made the IPA
    scan. What is left for a *point*: the SPA plugin has to carry rectangles
    (SPA's own rectangle type is a size with no origin, so it would have to be
    an array of four ints), and the app has to turn a tap into a window. Both
    are upstream work in PipeWire, not on this phone.
33h. **The front sensor answers, and what is left is a licence question.**
    2026-08-03 on `linux-fp3-7.1.3-r36`: `s5k4h7 1-0010: S5K4H7 detected, model
    ID 0x487b`. It registers no subdevice, so `cam -l` still reports one camera
    and **no application can show a front view**. Every rail it needs was
    already in the board file - `pm8953_l22` also feeds the rear sensor and
    `vreg_cam2_dig_1p2` on GPIO 46 was declared and unused - with reset on GPIO
    129, MCLK1, CCI master 1 and a 270 degree mount, all read out of
    Fairphone's downstream `msm8953-camera-sensor-mtp.dtsi`, which also puts it
    on CSIPHY2/CSID1.

    ☠️ **The one thing that was actually missing was the pinmux, and the board
    file removed it.** `msm8953.dtsi` muxes both CCI buses on the controller
    (`pinctrl-0 = <&cci0_default &cci1_default>`), but this board overrode
    `pinctrl-0` to add its MCLK0 pin and dropped `cci1_default` in the process,
    so the second bus had no pins and MCLK1 never reached the sensor. The
    symptom told the story once read properly: `-110` is a transfer that never
    completed, where an absent device gives `-ENXIO`. Everything else was
    already right, which is what left the pins as the only candidate.

    ☠️ **A `-110` from `imx363 0-001a` at boot is *not* related, and looked
    exactly as if it were.** It lands ~300 ms after the front sensor is
    detected, in every boot. Moving `s5k4h7.ko` aside and rebooting shows the
    same error with the driver absent, so it predates this work; the rear
    camera binds, keeps 24 media entities and captures normally either side of
    the change.

    ☠️ **No port yet, deliberately.** CAMSS does not finish registering until
    every endpoint in its graph binds a subdevice, so wiring this sensor in
    before its driver registers one would stall the notifier and take the
    working rear camera down with it.

    **What blocks it is a licence question, not engineering.** There is no
    mainline V4L2 driver for this part anywhere - searched, and the one
    mainline-adjacent project that mentions the sensor supports the hi846
    variant of the same board instead. The register sequences exist only in
    vendor Android trees (MediaTek `imgsensor`, a Qualcomm CAMX
    `s5k4h7_setting.h`), and the ones found **carry no licence statement at
    all**: no SPDX line, no GPL notice, no `MODULE_LICENSE`. Copying them into a
    GPL-2.0 file is the same class of decision as the actuator in the licence
    audit, and it is a human's. What the bring-up driver does use is the model
    ID and where to read it - register 0x0000 holds 0x487b - which is a fact
    about the hardware, corroborated independently in two vendor trees.
33i. **The libcamera package installs a menu entry for a binary it does not
    build.** The aport ships `qcam.desktop` while building with
    `-Dqcam=disabled`, so `/usr/share/applications/qcam.desktop` points at a
    missing `/usr/bin/qcam`. Either drop the desktop file or build `qcam` - it
    would be a useful instrument, since it can set AF controls without going
    through PipeWire at all, but it pulls Qt onto a phone.

33j. **The focus lens is not related to any distance, so manual focus cannot be
    offered.** Everything else the camera does is now settable by hand -
    exposure time, gain, white balance - but `LensPosition` is defined in
    dioptres, and the IPA refuses to publish a dioptre it cannot mean
    (`0104-ipa-simple-Allow-the-focus-to-be-set-where-the-lens-.patch`). Two
    numbers unlock it, both in the tuning file: `lens-infinity-code`, and
    `lens-closest-code` with the `lens-closest-distance` it focuses at.

    Two ways to get them, in increasing order of trustworthiness. **Measured:**
    point the camera at a detailed target at a tape-measured distance, run
    `focus-sweep.py --lo/--hi` around the peak, and record the code; repeat far
    away for the infinity end. **Read out:** the module carries its own
    calibration EEPROM (`bl24s64` at CCI 0x50, no driver), which is where the
    vendor keeps exactly these two codes - the honest source, and the one that
    would be right for every FP3 rather than for this unit.

    Until then the lens still focuses - by itself, or on a tap - it just cannot
    be told a distance, and the app shows no focus row because the camera
    advertises none.
## `wip/7.1.3/sensor` — SMGR over QMI/QRTR

Accelerometer, gyroscope, magnetometer, proximity, ambient light. Only one commit
has been distilled — `soc: qcom: qmi: read QMI_DATA_LEN at its declared width` —
and that is the whole submittable set, not a backlog. Re-verified **2026-08-01**
against today's `torvalds/linux`: the `Fixes:` hash resolves with a matching
subject, the patch applies clean to the current `qmi_encdec.c`, and
`checkpatch --strict` is silent. ☠️ Everything else is **unsendable rather than
undone**: `smgr_accel.c`, `drivers/iio/common/qcom_smgr/` and `net/qrtr`'s bus
conversion all 404 against mainline, so ten of our eleven remaining commits and
both QRTR prerequisites patch files that do not exist upstream — **including the
mount-matrix fix of item 27, which otherwise looks like an ideal standalone
submission.** The reasoning, and the cheap check that settles it before any
distillation work, are in
[`docs/sensors/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/sensors/README.md#why-the-submit-series-is-one-patch).
Gaps, in
[`docs/sensors/README.md`](https://github.com/llg179org/fp3-pmaports/blob/main/docs/sensors/README.md#known-gaps):

29. **`snsregd.py` is still a Python stand-in** for upstream's C `sns-reg`; it
    should become an aport. (Userspace, tracked here because the driver depends on
    it.)

## `wip/7.1.3/voice` — q6voice / CS-Voice over SLIMbus

One commit. Working on the device; see item 9 for why it is not sendable.

## The `debug` layer — bring-up aids, never upstream-bound

One commit: the watchdog started at probe. Nothing here gets a `submit/` series,
ever, and it stays off `integration/7.1.3`.

**It is the only category with no `wip` branch.** `wip/7.1.3/debug` was retired on
2026-07-30 (kept as the tag `archive/wip-7.1.3-debug-final`) once the layer became
reproducible without it: every other category needs a `wip` branch because it
carries evolving work against a moving base, while this one is a fixed, additive
change that replays anywhere. It now lives as that one commit on
`debug-int/<base>` plus the payloads in `fp3-pmaports/docs/debug/files/`, and
those payloads are half of the storage rather than a copy — refresh them in the
same commit that changes the layer.

The watchdog commit is the one place in the tree where mixing `.dts` with `.c` is
allowed, and it uses that licence: it adds an undocumented `qcom,start-at-probe`
property. That would be fatal in a `submit/` series and is fine here; the reason
is written into the commit message, along with why there is deliberately no
`ramoops` node (tried at `0x8ee00000` and at `0xd0000000`; nothing survives a
reset on this device, so it would cost 2 MB and imply a post-mortem capability
that does not exist).

### Replaying the debug layer onto any branch

The safety net is worth having on any branch you are about to boot — an
experimental offshoot is exactly where an early hang is likely, and exactly where
nobody wants to walk to the phone. One command, from the target branch:

```sh
git am ../fp3-pmaports/docs/debug/files/0001-watchdog-*.patch
```

The step-by-step — preconditions with defined failure actions, a by-hand
reconstruction for when the patch stops applying, and verification in three
places — is `fp3-pmaports/docs/debug/create_debug.md`.

It applies clean everywhere because the board-side change is a **separate**
`sdm632-fairphone-fp3-debug.dtsi` plus one `#include` among the other includes.
That is not cosmetic: every other category appends its nodes to the *end* of
`sdm632-fairphone-fp3.dts`, so the earlier form — which appended there too —
collided with whichever of them was present. Measured 2026-07-30: the appended
form conflicted on `wip/7.1.3/audio` and on `integration/7.1.3` and applied clean
on `camera` and `charger`; the split form applies clean on all five wip branches
and on integration. Verified again by rebuilding the layer from the stored
payloads onto a fresh branch off `integration/7.1.3`: same tree object as
`debug-int/7.1.3`, same blob for every file it touches.

---

## Not kernel work, kept here so it is not lost

30. **The notification LED blinks forever after a missed call** (`rgb:status`, not
    the flash). The real bug is a missing `EndFeedback` call in whatever raised it
    — phosh or the call app; secondarily, a `fairphone,fp3.json` feedbackd theme
    is missing.
31. **Untested: the interconnect path for the SCM/crypto node.** Non-blocking;
    kept in case the ADSP-boot timing question reopens.
33. **The camera app's *Find Best Size* measures the wrong quantity, and had
    settled on the worst size on the ladder.** It bisects the offered sizes and
    keeps the largest that still delivers frames — and 3840x2400 does deliver
    frames, at 7.1 fps, which is what a choppy viewfinder looks like. The step
    that decides the cost is invisible to it: a request that does not fit inside
    1912x1080 makes libcamera read out the full 4032x3024 sensor instead of the
    1920x1080 mode. Setting `preview-resolution` to 1680x1050 — the largest
    offered size that fits — measured 22.8 fps against 7.1, and is a gsettings
    change, not a rebuild. What should replace the frame-rate criterion in the
    search is the open question; the measurements are in
    [`camera/README.md`](camera/README.md#why-the-sensor-is-always-read-out-whole-and-what-it-costs).

35. **The camera app renders in software, and so does everything else.** The
    distro sets `GSK_RENDERER=cairo` session-wide for the a506; with a
    viewfinder running that costs 130% of a core in the app against 32% under
    `gl`, and it is why an interface stutters while the compositor sits at 2%.
    Overridden per user here, not in the package-owned file. Open: the app is
    reported to freeze under `gl`, with no core dump and nothing in the kernel
    log, so whether the distro's choice is protecting against something real on
    this GPU is not yet settled.

## The `vendor/*` and `archive/*` namespaces

Neither is a base and neither is ever pruned when a base is rolled.

- `vendor/imx363-sdm670`, `vendor/q6voice-sdm670` — **parentless snapshots** of
  third-party imports, made with `git commit-tree` and no `-p`, so the tree is
  byte-identical to the source without dragging in 71,541 unrelated commits.
  `git diff <snapshot> <source>` is empty, which is the check.
- `vendor/asoc-msm8953-base`, `vendor/q6voice-base` — tags, not branches: those
  commits are already in `7.1.3/main`, so they need a name, not a copy.
- `archive/*` — rewritten history kept reachable, so an old pin still resolves
  and its tarball still downloads.

## 🔨 T1 — learn `charge_full`: **written and building as r79 (2026-08-29)**

Measured: a full sweep of `ocv-capacity-table-0` (4.3756 V → 3.000 V) yields
**2175 mAh** on this pack against a declared `charge-full-design-microamp-hours =
<3060000>`, and **2076 mAh** down to the declared 3.400 V cutoff. One table-percent
is worth 21.8 mAh, not 30.6, and the 35 % floor the gauge stopped at is exactly
`1 − 2185/3060`. ☠️ **Do not fix it by editing the DT design value** — it is a
nameplate, the OCV table was characterised against it, and this is one aged pack;
that edit is right on this phone and wrong as a statement about the hardware, and
it is unsendable upstream.

The change, in `qcom_smbx.c` (charger category — so `wip/7.1.3/charger`, cherry-pick
to `integration/7.1.3`, carry to `debug-int/7.1.3`, push, then bump `_commit`):

1. Add `chip->charge_full_uah`, seeded from `batt_info->charge_full_design_uah`.
   `POWER_SUPPLY_PROP_CHARGE_FULL` returns it; `CHARGE_FULL_DESIGN` keeps returning
   the DT value. They stop being the same case label.
2. Divide by it, not by the design value, in the counting branch of the gauge
   (`per_permyriad = 360LL * chip->charge_full_uah`) and in `CHARGE_NOW`.
3. Learn between two *trusted* anchors — the points where the driver already
   overwrites `soc_permyriad` outright rather than counting: charge termination
   (100 %), an `S3_GOOD_OCV` re-anchor, and a quiet-current wake sample. Accumulate
   the counted charge between consecutive anchors; when the span is large enough
   (≥ 50 % and one-directional) set `full = accumulated_uah * 10000 / span`, blend
   ~25 % toward it rather than jumping, and clamp to 50–110 % of design.
4. Persist it beside the SoC byte in the gauge's scratch SRAM, behind the same
   magic, so a warm reboot does not throw the learning away. A battery swap clears
   the magic and the value falls back to design, which is the correct behaviour.

**Implemented 2026-08-29** as `power: supply: qcom_smbx: learn what the pack
actually holds` — `wip/7.1.3/charger 56ed6005`, `integration/7.1.3 bbb5a088`,
`debug-int/7.1.3 b8de6ded`, all pushed and tarball-reachable, package bumped to
r79. Two departures from the sketch above, both to keep the arithmetic honest:
the accumulator is **signed**, so a span whose charge disagrees with its direction
is discarded rather than averaged; and a stale gap either **starts** a new span
(when the wake sample is itself at rest, which makes it an anchor) or **ends
learning** (when it is not), because charge that moved uncounted would otherwise
be divided by a span that includes it.

☠️ **The `.ko` hot-swap was tried first and must not be.** A module built from
`wip/7.1.3/charger` and loaded onto a phone running `debug-int/7.1.3` fails with
an `ftrace bug`, leaves the charger unbound and wedges `/proc/modules` — and the
on-disk module had already been overwritten, so the next boot would have had no
charger driver. Recovered from the r78 `.apk`. Build the module from the tree the
phone runs, or use the package.

Expected convergence: **~2076 mAh**. Evidence that it worked: a discharge segment
where the ratio of mAh delivered to percent lost lands at 20.8 (2076/100), and a
run that reaches 0 % at the 3.400 V cutoff instead of stopping at 35 %.

☠️ Validation needs a full pack cycle, so this does not go in front of a power
measurement that needs the current kernel. **T2 is not a separate item** — there is
no low-voltage cutoff in `qcom_smbx.c` and there should not be; on mainline the
shutdown is UPower's policy driven by `capacity`, so fixing the percentage fixes
the 2.864 V run too.

## ★★★★★ 2026-08-28 evening — the road to halving pmOS, in order

The target in numbers: idle **98–101 mA → ≤50 mA**, call-wake preserved. It rests
largely on **one** term — the modem core is awake **33–36 %** against the oracle's
**6.3 %** — because with the core down this phone idles at **57.5 mA**, inside the
oracle's own 55–64 mA band.

★★★★★ **2026-08-29 — the model closes, and the target is below the modem.** One
line fitted on the radio-low legs explains **both** systems:

```
current_mA = 54.9 + 135.0 * MPSS_duty
```
6.1 % → **63.1 mA** (oracle measured 55–64) · 34.8 % → **101.9 mA** (pmOS measured
98–101). ☠️ This retracts the "~15 mA has no owner" written here earlier the same
day: that multiplied one run's floor by another run's coefficient. Nothing is left
over.

**So the road forks, and the two halves of the goal need different work:**

- **Parity with the oracle (55–64 mA) is the modem term, and only that.** Taking the
  duty from 34.8 % to 6.1 % lands at 63 mA. That is this front's ceiling.
- **The halving target (≤50 mA) is below the intercept.** With the modem core
  powered down for good the phone still draws ~55 mA, and the p10 floor is 53–54 mA
  in all three legs whatever the modem does. **No modem fix reaches it.** Going
  lower has to come out of the intercept — the AP, the WiFi core and the SoC — where
  `APSS XO off` has read **0.0 s in every window ever taken on either system**.
  **Suspend residency is the only route to the target at all**, which is the
  opposite of what was written here for two days.

★ What is measured and shippable so far is **zero**. The band is worth 12 mA and is
not shippable (pinning an LTE band trades coverage for power); 2G is worth 44 mA
and is an instrument; the eMMC autosuspend delay is a dead knob (three rounds, no
effect).

☠️ **2G is an instrument, not a mode.** The `2gonly` A-B-A′ answers whether the
cost is RAT/DRX-dependent, which names *where* a fix would live. The networks are
being switched off; nothing here proposes shipping it.

### 0. ★★★★★ NEW PRIMARY — get below the 54.9 mA intercept, which means suspend

Everything under §1 and after buys **parity** with the oracle and stops at 63 mA.
The halving target lives under the intercept, and the intercept is an application
processor that has **never slept** — `APSS XO off` reads 0.0 s in every window ever
taken, on either system.

The blocker is already named: `pm_wakeup_irq = 141` on 4 of 4 attempts, the
**modem's SMD edge**, and the modem rings it about **once every fourteen seconds**
(0.07 /s by hardware IRQ). The measured sleep durations line up with exactly that
interval — 60 / 2 / 9 / 6 / 6 / 19 s out of 600 s attempts.

☠️ **And today that traffic is pure loss.** The modem edge
(`remoteproc0:smd-edge`) currently reads `power/wakeup = disabled`, so it breaks
the suspend *without* being able to deliver a call. Whatever the fix is, the phone
is paying the cost and getting none of the benefit.

**The ordered questions, none of which needs a new instrument:**

1. **Is the ~14 s ring ours?** Two boots, same instrument: ModemManager running,
   against ModemManager masked from boot with the modem brought online by a single
   `qmicli --dms-set-operating-mode=online` and no indications subscribed. Compare
   `modem_irq_per_s` and the suspend-round durations (`suspend-rate.sh`). The 2026-08-22
   census put the ring on **IPCRTR** and found it signal-level — flow control and
   read-acks, not messages — and found the AP sending almost nothing, so a
   subscription the modem is *answering* is the obvious remaining candidate.
2. **If it is ours**, name the indication (signal strength, serving system) and
   measure the residency with it off. That is a userspace fix and it is shippable.
3. **If it is not ours**, the question becomes why a non-wake interrupt aborts
   s2idle at all, which is a kernel question about this edge's IRQ handling.
4. **Only then** turn the policy layer on — `IdleAction`, gsd-power's
   `sleep-inactive-battery-type` — and measure what residency is worth in mA. Until
   a suspend can hold, enabling the policy measures nothing.

### 1. ⏳ The decisive fork — is it our stack's configuration or the modem's own?

Boot with **`ModemManager` masked from boot**, then 2 × 360 s of MPSS duty.
- duty still 33–36 % → the modem behaves this way on its own NV/EFS configuration,
  and the fix is a QMI/NV request we never send;
- duty drops → our stack asks for it, and the fix is in what ModemManager requests.

☠️ The 2026-08-27 "ModemManager stop" A-B-A′ (38/36/37 %, flat) does **not** answer
this: a daemon stopped mid-run does not un-configure what it already set. The boot
is the difference. ☠️ Keep `rmtfs`/`tqftpserv` running — without EFS the modem does
not run at all, and a crash-looping modem is a third state, not a control.
*Cost: one reboot + ~20 min.*

### 2. ⏳ The matched QMI census, both sides — one slot switch, three questions

- which QMI services each stack opens and **which indications it registers for**;
  a short DRX preference or a dense NAS event report is exactly the shape of thing
  that keeps a modem awake while sending the AP nothing;
- **retake the oracle's 565 s window with the radio state written into the
  capture** — today's `--set-power-state-low` result rules out a powered-down
  modem (that reads 0.0 %), but the registration state is still undocumented;
- ☠️ **signal quality and serving cell on both sides.** The two measurements are
  from different days; a modem in poor coverage stays awake more. This is a live
  confound and neither side has ever recorded it.
*Cost: one slot switch, ~40 min. The first step that needs one.*

### 3. ⏳ Only if 1 and 2 name nothing — the DIAG side

QCSuper is in the workspace and the DIAG channels exist (all UNBOUND). The question
is what the modem firmware does during its awake windows. Hours, not minutes.

### 4. ⏳ The fix, and on today's evidence it is not a kernel patch

A QMI request pmOS never sends (power-save / DRX preference), an indication
registration to drop, or an NV item. All three are userspace. The 28-commit power
layer fixed the floor and the wakeup count (median −35 %, `cluster-pc` and
`system-pc` from zero); **none of it touches the modem core.**

### 5. ⏳ The responsiveness half, which probably resolves with 4

Even at UT's consumption the phone never sleeps: `suspend_stats/success = 0`,
`IdleAction=ignore`, `sleep-inactive-battery-type='nothing'` — not blocked, never
requested.

> ☠️ **Read "never sleeps" as "is never asked to", which is what the evidence
> says.** Once asked, it does: on 2026-08-30 it completed **600, 600, 601 and
> 600 s** windows back to back, each filling its alarm, radio up and registered.
> The same configuration also produced six consecutive 52–63 s sleeps that
> morning, so the sentence below about a ~2 s ring is one regime rather than a
> property — see `power/bringup/leads/sleep-length-is-a-state.md`. What has not
> changed is the policy: nothing on this system requests a suspend on its own,
> so every one of those numbers came from an explicit `systemctl suspend`. And when requested it holds ~7.5 s, because the armed modem edge rings
about every 2 s (IPCRTR, signal-level). ☠️ That channel is also how a call arrives,
so the channel is not a lever — but the ring is the modem's own behaviour, so if 4
stops the modem waking, it likely stops the ring. **Then** enable the idle-suspend
policy and re-measure residency *and* call-wake latency on the same configuration.

☠️ Expectation correction: **the oracle does not sleep either** (2 completed
suspends of 120). Sleep is headroom below *both*, not the difference between them,
and halving does not need it — the modem term alone takes 98–101 mA to ~57.

### 6. ⏳ For the report, not for the physics — T1

The gauge divides by the nameplate: this pack yields 2175 mAh across the OCV
table's full span against a declared 3060, so `capacity` floors at 35 % and UPower
never acts. Until that is fixed, "we halved the consumption" cannot be converted
into runtime. Design settled above; validation costs a pack cycle.

## ⏳ Queued 2026-08-28 night — if the QMI-client test reads ~35 %

Then no client configuration causes it, and the difference is something the vendor
stack **actively asks for**. The candidate the evidence points at is the **IPA
control path**: `qrtr-lookup` on pmOS lists an *IPA control service* (49) offered by
the modem with nobody talking to it, the IPA hardware is probed
(`7900000.ipa`, driver `ipa`) and no channel is ever brought up, while the oracle
runs `ipacm` and `ipacm-diag` and holds `rmnet_data2` fully established. A modem
whose hardware data path was never negotiated has a reason to keep its core
serviceable.

**The decisive test is on the oracle, not on us:** stop `ipacm` there and re-measure
its duty with `modem-window.sh`. If 6.1 % rises toward 35 %, the mechanism is named
exactly, and it is named on the system that works — which is the stronger direction
to prove it in.

*Cost: one slot switch, ~25 min.* ☠️ Restore `ipacm` before switching back; it is
the vendor data path and leaving it down would make the oracle's next capture a
different phone.

Second candidate if that is flat: the **DIAG channels**, which are all UNBOUND on
pmOS and drained by `ipacm-diag` on the oracle.
