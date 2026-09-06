# ★ The network DOES allow IMS voice to this device — the IMEI/TAC gate is not the answer

2026-09-06, pmOS `linux-fp3-7.1.3-r88`. Closes the open question in
[`leads/imei-tac-gating.md`](../../leads/imei-tac-gating.md), which said the
measurement was decisive and that nothing we held could make it.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely. No NAS bytes are reproduced: an ATTACH ACCEPT
> carries a GUTI and the TAI list, and the decoder prints IEIs and lengths only.

## The result

```
EMM messages seen: ATTACH REQUEST, AUTH REQUEST, AUTH RESPONSE,
                   SECURITY MODE COMMAND, SECURITY MODE COMPLETE,
                   ATTACH ACCEPT, ATTACH COMPLETE
  ATTACH ACCEPT  IEs closed=True (5 IEs)  IMS voice over PS = SUPPORTED
```

TS 24.301 9.9.3.12A, IEI `0x64` "EPS network feature support", octet 3 bit 1.
**The network tells this UE, in this tracking area, that it may use IMS for
voice.** So the refusal is not device policy, and
[`leads/imei-tac-gating.md`](../../leads/imei-tac-gating.md)'s own framing
applies: *"the refusal is not at that layer and the fault is below ofono, on our
side."*

That removes the cheapest remaining explanation for the `500` that
[`../2026-09-05_imsd-first-register/`](../2026-09-05_imsd-first-register/)
records, and it means VoLTE here is not blocked by the operator refusing the
handset.

## How the capture was finally taken, after four failures

Every earlier attempt returned paging and nothing else. The reasons, in order:

1. ☠️ **`mmcli -m 0`, hardcoded.** The modem renumbered to `Modem/1` after a
   reinitialisation, so every command returned rc=1 while the script reported
   progress. The index is an allocation, exactly like the i2c bus number and the
   input node elsewhere on this device. `-m any` throughout.
2. ☠️ **The DIAG control handshake is answered ONCE PER BOOT** — and
   `tools/diag-log-capture.py` says so in its own header, at line 47, just past
   where the first reading stopped. The first run of a boot draws ~6 kB on the
   control endpoint and its log mask takes effect; every later run draws 9 bytes
   and streams RRC only. Attempts 2-4 each contained a real attach and could not
   have recorded it. **A retry is a reboot, not a re-run.**
3. **`--disable` alone leaves the modem camped.** A real detach needs
   `--set-power-state-low`, and the attach then happens inside the window.

The working recipe is `attach-capture.sh` beside this page: reboot, then one run
that starts the capture and cycles the RF inside it.

## The decoder, and the two ways it was wrong first

`vops-diag.py` joins the entry framing of `tools/diag-ota-decode.py` to the IE
walk of the earlier `vops-scan.py`, which wanted a pcap it will never get here.

- The **ESM message container is LV-E**: a two-octet length (TS 24.301 8.2.1).
  Reading one octet put the walk inside the container.
- ☠️ **Not every optional IE is TLV.** `0x13` (Location area identification) is
  type 3, fixed length, with no length octet. Read as TLV it gave `L=18` and
  every offset after it was fiction.

Both times the walk overran, and both times **the `closed` guard refused to
produce a verdict** — which is the only reason a wrong answer was not published.
`leads/imei-tac-gating.md` demanded exactly that guard, because this repo has
already published one wrong conclusion from a scanner that searched too widely.

**Known-answer control**: the same decoder over
`captures/2026-09-02_diag-ota-pmos/raw/diag.bin` reports *no ATTACH ACCEPT*,
which is what that page records for it (one EMM entry, no Accept, the device
already registered for the whole window).

## What this does not say

It does not explain the `500`. It removes device policy as the reason and puts
the fault back on our side or in the core's handling of this particular
registration. The next instruments are unchanged: the stock-stack REGISTER to
diff against, and the carrier configuration (#166) that is still unloaded.
