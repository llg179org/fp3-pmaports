> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

# Our wakes are seven times too long, and the RAT list is the first candidate

**Opened 2026-09-01**, on the back of the two-slot window
([`../captures/2026-09-01_both-slots/`](../captures/2026-09-01_both-slots/README.md)).

## The shape of the problem

Both stacks wake the modem at the **same rate** — 3.14 XO exits per second on the
oracle, 2.38 on ours — and the whole 30-point duty gap is **how long it stays
up**: 22 ms per wake on the oracle, **157 ms on ours**.

☠️ **That rules out an AP poll as the cause.** Nothing ModemManager does runs at
2.4 Hz. The extra 135 ms is work the modem performs *per paging occasion*, and
the classic reason a UE spends longer at each occasion is measurement it was told
to do.

## What we are telling it to do

Read 2026-09-01 16:07 (`--nas-get-system-selection-preference`):

```
Mode preference: 'cdma-1x, cdma-1xevdo, gsm, umts, lte, td-scdma'
Acquisition order preference: 'lte, umts, gsm, cdma-1x, cdma-1xevdo'
```

Every RAT the chip can do, on a 3GPP-only SIM in a network that has GSM, UMTS
and LTE. A UE with GSM and UMTS in its mode preference runs inter-RAT
measurements when the serving cell's level falls below the reselection
thresholds — and our serving RSRP has been −85 to −95 dBm all afternoon.

## ★ Where that list comes from — read from source, not guessed

`mm-shared-qmi.c:696-713` (`set_current_capabilities_system_selection_preference`):

```c
pref = mm_modem_capability_to_qmi_rat_mode_preference (ctx->capabilities);
...
qmi_message_nas_set_system_selection_preference_input_set_mode_preference (input, pref, NULL);
qmi_message_nas_set_system_selection_preference_input_set_change_duration (input, QMI_NAS_CHANGE_DURATION_PERMANENT, NULL);
```

**ModemManager writes the RAT list itself, derived from everything the chip
claims to support, and writes it `PERMANENT`** — i.e. into the modem's own
persistent state.

☠️ **This qualifies the structural elimination made earlier the same day.** The
argument there was that modem NV cannot carry a stack difference because both
slots see the same NV. That is still true of *simultaneous* state — but
`CHANGE_DURATION_PERMANENT` is the bridge: an **AP-side decision gets written
into modem-persistent storage and stays there for the other slot**. So the NV
can carry a trace of *which stack booted last*, which is exactly the shape the
unexplained 2026-08-31 episode has.

☠️ **What is NOT established**: that this code path runs on every boot. It is
reached from `set_current_capabilities`, i.e. when something asks to change
capabilities, not unconditionally at startup. Do not write "MM sets this at
boot" until it has been seen in a log or a trace.

## The test, running as this page is written

[`../tools/mode-ladder.sh`](../tools/mode-ladder.sh) — `lte` /
`gsm|umts|lte` / `lte` again, 600 s each, inside one boot, first mode repeated
last so the knob can be told from drift.

**Pre-registered:** LTE-only meaningfully below the ~34 % baseline ⇒ the
mechanism is inter-RAT work and there is a lever. No change ⇒ IRAT is out and
the 135 ms is something else the modem does per occasion.

☠️ **An LTE-only phone cannot receive a CSFB call**, and this device has no IMS.
That is fine for a measurement window and is not a shippable default; the tool's
restore is unconditional and verified by re-reading.

## Two traps this tool had to be taught, both already known here

- The qmicli argument is the mode list itself, not `mode-preference=…`.
- The preference is **printed** comma-separated (`gsm, umts, lte`) and
  **accepted** pipe-separated (`gsm|umts|lte`). Writing back what was printed
  fails — the identical trap `band-ab.sh` documents for the band list, and it
  fails into a restore that silently does not happen. The ladder translates, and
  then re-reads to prove the restore took.
