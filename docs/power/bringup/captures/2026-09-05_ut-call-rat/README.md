# The UT oracle falls back to 2G too — the dependency is not our missing IMS stack

2026-09-05 04:34, UT oracle slot (slot a), same device, same IMEI, same card.
Raw: `rat-timeline.txt` (the RAT sampled ~0.5 Hz), `calls-journal.txt`.

## The measurement

```
04:34:21   tech=edge  reg=registered  ims=1     <- 2G, before the ring
04:34:22   playIncomingCallSound                   the phone rang
04:34:21 … 04:34:33   tech=edge throughout
04:34:34   call channel closed
04:34:35   tech=lte                              <- back on LTE, one second after teardown
```

The radio drops to EDGE for the call and returns to LTE the second it ends.
That is CSFB, measured directly, on the oracle.

☠️ **`ims=1` holds through the entire EDGE window.** IMS is registered while the
call is delivered over CS. So on this subscription, **IMS registration does not
imply VoLTE for an incoming call** — the two are independent.

## ☠️ RETRACTION — what this overturns, written the same night

Earlier the same night this project inferred the opposite, from two calls
(04:20 and 04:29) whose only evidence was the journal:

```
04:20:34  imsradio0 > 6 onServiceStatusChanged   ×3     (2 s before the call)
04:20:36  new call, State=incoming
04:20:46  imsradio0 > 27 ??? and onServiceStatusChanged
04:20:47  call channel closed
```

That was read as *"the IMS radio brackets the call, therefore IMS carried it,
therefore UT rings on 4G"*. **It is wrong.** The same bracketing appears on the
04:34 call, which the direct sampling shows was on EDGE from start to finish —
so `imsradio0` service-status changes are equally consistent with IMS being
suspended and resumed *around* a CSFB, which is what actually happens.

The failure mode is worth naming because it is not carelessness: the indirect
signal was real, reproducible, and pointed one way; the direct measurement
pointed the other. **A signal that brackets an event does not tell you what
carried it.**

And a second retraction follows from the first. The night's earlier conclusion —
*"the 2G dependency is ours, not the network's: the operator carries VoLTE and
admits this IMEI, so it is our missing IMS stack that forces CSFB"* — is
**backwards**. The oracle runs the full vendor IMS stack, is IMS-registered, and
still receives the call on EDGE.

## What it does to the `imsd` path

`leads/imsd-cost-estimate.md` prices `imsd` as a **contingency against 2G
retirement**: *"if 2G goes, it is what is left"*. That premise no longer holds on
the evidence available. Writing `imsd` would give pmOS what UT already has — and
UT still falls back. On this card, a working IMS stack is **not** what stands
between us and a VoLTE call.

It does not make `imsd` worthless (it remains the way to stop the 8.5 s PDN retry
loop that costs ~42 duty points), but its **insurance value against 2G going away
is not demonstrated**, and the page that claims it needs this reading beside it.

## What is still open, and the cheap test that would close it

The variable is now most likely the **subscription**, exactly as it was for the
daily handset: on that phone, measured 2026-09-03, one vodafone HU SIM keeps 4G
through a call and the other falls to GSM/EDGE, and the difference is the
**tariff** (private vs corporate). The dev phone carries a **third** card, on
neither plan, never characterised on its own.

☠️ The decisive test needs no flashing and no new software: **put the dev SIM in
the daily factory-Android handset and call it.** Same certified stack that gives
VoLTE on the private SIM, same network, same place — one variable, the card.

* falls back there too ⇒ the card is the variable, and neither `imsd` nor a
  factory Android on the dev phone changes anything;
* rings on 4G there ⇒ the certified stack gets what the vendor IMS on UT does
  not, and the software side is worth looking at after all.

Reading it: during a call Android's **status bar does not show the network type**
(measured 2026-09-03). Use *Settings → About phone → SIM status → "Mobile network
type"*, which updates live, or turn WiFi off on the calling handset and see
whether mobile data keeps working through the call.

## Instrument notes, because three attempts failed first

* ☠️ **`pkill -f ut-callwatch` killed the ssh session running it.** The pattern
  matched the command line of my own remote shell, so every attempt that began
  with it died mid-setup and read exactly like a flaky link. Two of the
  operator's calls were lost to this. Do not pkill by a pattern your own command
  line contains.
* ☠️ **`| tail -N` on a backgrounded run buffers until EOF.** The first call was
  sampled correctly and the samples were destroyed when the task was stopped,
  because nothing had been flushed. Write to a file on the device and read the
  file.
* The `states=` column in `rat-timeline.txt` is **unreliable** — it picks up the
  first `State =` in the modem dump, which is SupplementaryServices, not the
  call. The call boundaries come from the journal, and they align with the RAT
  transitions to the second.
