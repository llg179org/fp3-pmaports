<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# The duty result is now airtight. The milliamps are still not measured — and this run says why.

`tools/ims-ma2.sh 30 600 eutran-1`, 2026-09-02 04:10–06:01, one boot, on battery
(USB input suspended in the PMIC), AP suspended in 600 s rtcwake cycles, band
pinned and sampled at **every** wake. A 20-minute settling leg ran first and was
discarded.

## ★ The duty: the cleanest A/B/A' this repo has produced

| leg | IMS | MPSS duty | wakes/s | ms/wake |
|---|---|---:|---:|---:|
| A  | on  | 48.0 % | 2.53 | 189.7 |
| **B**  | **off** | **4.4 %** | **3.15** | **14.1** |
| A' | on  | 47.6 % | 2.53 | 188.0 |

A' brackets A to **0.4 pp**. Every sample in all four legs read band `eutran-1`,
cell `1470762` — pinned and verified, not assumed. B's 3.15 wakes/s is 1/318 ms,
the paging DRX cycle, at 14.1 ms a wake: `RRC_IDLE`, camped.

This is the third independent measurement of the same effect (ladder 44.5→4.8,
first census 45.6→asleep, this one 48.0→4.4) and the tightest.

## ☠️ The milliamps: both instruments failed, and the data shows it

| leg | ΔV over the leg | `current_now` median |
|---|---:|---:|
| settle | −361 mV/h | −138.5 mA |
| A | −326 mV/h | −148.0 mA |
| B | **+1.7 mV/h** | −107.6 mA |
| A' | −172 mV/h | −202.9 mA |

Neither column can be quoted, and the reason is visible inside the numbers:

- **The voltage is load transient, not state of charge.** Leg A ends at
  4 070 638 µV and leg B *starts* at 4 172 433 µV — a 100 mV rise between two
  consecutive readings minutes apart. `voltage_now` is a terminal voltage sampled
  immediately after wake, when the radio is drawing hard; the IR drop dominates
  and swamps the discharge. Feeding that into the reference curve produces
  1806 mA for leg A, which is enough on its own to reject the method here.
- **Three samples per leg.** A 30-minute leg with a 600 s alarm wakes three
  times. A median of three, of a quantity whose scatter is this large, is not a
  measurement — and A' (−202.9 mA) against A (−148.0 mA) shows the scatter
  directly, in two legs that are *the same configuration*.

`current_now` is nonetheless the right instrument and it does point one way:
B sits ~40 mA below A. But with A and A' 55 mA apart, that direction is not a
number.

## What this retracts, and what it costs

The previous census's **~40 mA for the cheap state does not gain support here** —
this better-controlled run says the voltage-slope method is unusable at this
timescale, and the earlier number came from exactly that method. It stands only
as "nothing contradicts it", which is where it was.

The 86 ± 4 mA figure this project trusts came from an **eight-hour, 86-round**
run. That is the instrument that works for a sleeping phone, and the current
front needs one of those per state — not 30-minute legs. Cost: two nights, or
one night with the arms interleaved.

☠️ Sampling immediately after wake is itself a fixable flaw: a fixed settling
delay before reading voltage would cut most of the IR-drop error. That belongs in
the night-long version.

## Raw

`raw/log.txt`, `raw/rounds-{settle,A,B,A2}.txt` (one line per wake: voltage,
current, capacity, band, cell, RSRP, registration state),
`raw/mpss-{A,B,A2}.txt`.
