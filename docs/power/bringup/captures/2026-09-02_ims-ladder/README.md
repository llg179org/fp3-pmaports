<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ★★★★★ The IMS loop is the duty gap: 44.5 % → 4.8 % → 46.8 %, band-pinned

`tools/ims-ab.sh 600`, 2026-09-02 01:38–02:11, one boot, one cell.
**The pre-registration hit on both counts it named**, and the repeat of the first
arm brackets it, so there is no drift to explain it away.

| leg | IMS | MPSS duty | wakes/s | ms/wake |
|---|---|---:|---:|---:|
| A  | on  | 44.5 % | 2.54 | 174.9 |
| **B**  | **off** | **4.8 %** | **3.13** | **15.4** |
| A' | on  | 46.8 % | 2.56 | 182.9 |

What was written down before the run: *"B at least 10 pp below the mean of A and
A' ⇒ the loop is causal; A ≈ B ≈ A' ⇒ the loop is a passenger and the capture's
causal claim must be retracted; A' materially different from A ⇒ a drift-loaded
ladder that says nothing."* B is **40.9 pp** below the A/A' mean of 45.7 %, and
A' sits 2.3 pp from A — inside this repo's ~3 pp repeatability.

★ **And the wake rate is the second, independent signature.** 3.13/s is
1/320 ms — the LTE paging DRX cycle. The cheap leg is not "the same behaviour,
less of it": it is a UE back in `RRC_IDLE`, camped, waking only for paging, at
15.4 ms a wake. That is the oracle's own fingerprint (6.9 %, 3.15/s, 20.0 ms) —
**measured here on our stack, and slightly cheaper than the oracle.**

## Why this ladder is believable where the first window was not

The 00:17 window was thrown out for two reasons; both are closed here.

- **DIAG residue** — the log mask is modem-side state that outlived the capture
  process. The ladder starts with a modem firmware restart, which clears it.
- **The band moved inside the window** (worth ~17 pp here). Every leg was pinned
  to `eutran-1` and every leg's before/after block reports **band `eutran-1`,
  cell `1470762`, serving RSRP ≈ −93 dBm**. Same radio, three times.

Each leg also reads the IMS switch vector back after writing it, so no leg rests
on the assumption that a write took: A and A' show voice/VoWiFi/video/SMS/UT
`True`, B shows all `False`.

## ☠️ The IMS write survives a modem firmware restart

Read immediately after the restart, before any write in this run:

```
voice False · VoWiFi False · video telephony False · SMS False · UT False · USSD False
```

The switches set the previous evening were still off. So the setting is
**modem-persistent** (NV-backed, or at least surviving a firmware reboot) — which
**confirms rather than lifts** the shared-state warning recorded in
[`../2026-09-01_both-slots/`](../2026-09-01_both-slots/): the modem NV is one
store for both A/B slots, so the write reached the oracle's modem too. It was
restored to `True` at the end of this run, read back.

☠️ `USSD` reads `False` even in the legs that wrote `True` — a third switch whose
setter and getter do not correspond. It is recorded, not explained.

## What this does NOT establish

- **The milliamps.** The whole ladder ran on the cable with the AP awake
  (`APSS` never entered XO shutdown in any leg), so the battery voltage in these
  files prices nothing. The model would put 4.8 % at 41.4 + 133 × 0.048 ≈ 48 mA,
  but that rests on a fitted slope with a ≥15 mA structural residual, and an
  awake-AP window is not the sleeping phone the goal is about. **The duty front
  is closed; the current front is not.**
- **Reachability.** IMS off means no VoLTE and no IMS-routed SMS. This device has
  never registered IMS, so calls are CSFB and the modem stayed `registered` and
  CS-attached throughout — but *"a call still rings"* and *"an SMS still
  arrives"* are tests, not inferences, and neither has been run.
- **Why the modem tears the PDN down.** Unchanged: still an unexplained local
  precondition, still the IMS/QIPCALL log families' question to answer.

## ★ Passenger result: PRONTO is not coupled to MPSS

Pre-registered in the plan (item 47): *if MPSS goes cheap, PRONTO returns to
~17–19 % and ~20 ms.* It does not — 24.9 / 25.5 / 25.7 % and 27.9 / 28.9 /
29.1 ms across the three legs, flat while MPSS moved by 40 pp. The WiFi core's
duty is set by its own transport, not by the modem's state. Cost: nothing, it
rode along in the same windows.

## Raw

`raw/log.txt` (the run, with the per-leg read-backs), `raw/window-{A,B,A2}.txt`
(the four-master windows with both radio-context blocks).
