# ModemManager is not the modem's duty — and the real differential is the ADSP

> ⚠️ AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.

**2026-08-31 05:38–06:12**, `tools/mm-duty-ab.sh 600 120`, one boot, uptime 16 h,
the daemon as the only deliberate variable, 120 s settle before each window.

## The A-B-A′

| leg | ModemManager | MPSS awake |
|---|---|---|
| A | stopped | **5.1 %** |
| B | **running** — `registered`, `access tech: lte`, `packet service state: attached`, vodafone HU | **4.9 %** |
| A′ | stopped | **4.9 %** |

**Flat.** The daemon is not what keeps the modem awake. The B leg's `mmcli` output
is in the capture and shows a live, attached LTE modem, so this is not a leg that
failed to run.

⇒ The hypothesis opened an hour earlier — *"our ModemManager is what drives the
34.8 % duty"* — is **retired**. It was written up as a plan item and never as a
finding, which is the only reason it cost nothing.

## ☠️ The bigger thing the same numbers say

The figure that has driven the whole modem track is **34.8 %**, from
`captures/2026-08-28_modem-window-both/pmos-lte.txt`. Today, same stack, same
operator, daemon running: **4.9 %**.

**The MPSS duty is not a standing property of this system.** It was 34.8 % on one
day and 4.9 % on another, and nothing in the plan explains the difference.
Everything built on "pmOS runs a 34.8 % modem duty" needs that caveat.

## ☠️☠️ CORRECTION — the LPASS finding below is a REDISCOVERY, not a discovery

Written before checking `leads/`. It was already there, measured four days
earlier with a better instrument:
[`../leads/lpass-never-sleeps.md`](../leads/lpass-never-sleeps.md), entry
2026-08-27, five independent `burst-master.sh` windows of 189 samples each —
`LPASS_xopct` **0 in every sample of every window**, `XO total duration` 9.4 s
against 5½ hours of uptime (**0.05 %**), against the oracle's **97.1 %** over a
565 s window. That page also carries a **root cause**: an unconditional
`clk_prepare_enable(mclk)` in the `msm8916-wcd-digital` probe, where on msm8953
mclk is a q6afecc ADSP clock request.

What the table below actually adds is small and worth keeping: the same fact is
visible in the `modem-window` captures too, so any run of that instrument can see
it without reaching for `burst-master.sh`. The stars were for a result somebody
had already written down.

☠️ The lead's own banner warns about exactly this failure — *"A closed result in
a file the resume path does not read is not a closed result"* — and it says the
2026-08-22 closing banner is **false on the device today**. So the open question
is not "is the LPASS awake" but "why is it still awake after r64's two fixes",
which that page owns.

## What was in the captures all along

`modem-window-fit.py` prints every master, every run. Read across the same files:

| capture | MPSS awake | **LPASS awake** |
|---|---|---|
| pmOS 2026-08-28 `pmos-lte.txt` | 34.8 % | **100.0 %** |
| pmOS 2026-08-31 leg A | 5.1 % | **100.0 %** |
| pmOS 2026-08-31 leg B | 4.9 % | **100.0 %** |
| pmOS 2026-08-31 leg A′ | 4.9 % | **100.0 %** |
| oracle `ut-lte.txt` | 6.1 % | **3.0 %** |
| oracle `ut-netmgrd-off.txt` | 5.3 % | **2.8 %** |
| oracle `ut-ipacm-on.txt` | 8.0 % | **2.9 %** |
| oracle `ut-ipacm-off.txt` | 6.6 % | **2.9 %** |
| oracle `ut-ipacm-off-real.txt` | 6.4 % | **2.9 %** |

☠️ **The 100 % is not an instrument artefact.** The same counter, the same script,
reads 2.8–3.0 % on the oracle — so it does report LPASS XO-off when there is any.
On pmOS the audio DSP **never lets the crystal go**, in every window ever taken,
while the oracle's is awake about 3 % of the time.

So the stable, two-sided, reproducible differential between the two systems is the
**LPASS**, not the MPSS. The modem figure moves between days; this one has not
moved in any capture.

## ☠️ Why this sat unread for three days

It was printed on every run since 2026-08-28. The attention was on the MPSS row
because the question was "the modem". **A four-master instrument was read as a
one-master instrument.** The habit that follows: read all four masters on every
`modem-window` run, and treat an unexpected **100 %** as a finding with the same
weight as the number you came for.

## What this does not say

* **What the awake LPASS costs in mA is unmeasured.** The fitted 135 mA-per-unit
  coefficient was regressed against *MPSS* duty; nothing licenses applying it here.
* **Whether the LPASS stays awake through s2idle is unmeasured**, and that is the
  question that matters for the unexplained ~41 mA of the 48 mA sleeping floor.
  A window is not a suspend.
* Nothing here says *why* the ADSP stays up. This project has prior art on the
  audio DSP refusing to power-collapse (`lpass-*` tools exist for that reason), and
  a mainline gap that points the same way is in
  [`../leads/smp2p-sleepstate-missing.md`](../leads/smp2p-sleepstate-missing.md) —
  whose sleepstate bit goes to **pid 2, the ADSP**. That lead was written earlier
  the same morning with the ADSP framing already correct, which is luck plus one
  grep, not foresight.
