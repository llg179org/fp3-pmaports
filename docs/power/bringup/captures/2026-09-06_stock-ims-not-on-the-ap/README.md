# ★ The stock IMS registration never touches the AP — so the oracle diff cannot be captured this way

2026-09-06, slot a, Ubuntu Touch 4.9.218, root. **A negative result, and it
closes a line three documents call "the right instrument".**

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely. The capture stayed on the device; only counts and
> masked summaries are reproduced.

## The question

[`../2026-09-05_imsd-first-register/`](../2026-09-05_imsd-first-register/) ends
by naming the instrument that would explain imsd's `500`: capture the **stock**
REGISTER and diff it header by header against ours. The unprotected REGISTER and
its 401 travel in the clear, before the IPsec SAs exist, so a packet capture
should be enough — no DIAG, no vendor tooling.

## The measurement

`tcpdump -i any`, no filter, spanning a full IMS re-registration forced by
taking ofono's modem `Online` false then true:

```
before: Online=true  IMS=true
        Online=false IMS=(gone)
        Online=true  IMS=true      <- registered again within 10 s
packets captured: 4965
  port 5060/5061 : 2      (a TCP ack and an RST on a leftover connection)
  ESP (proto 50) : 0
  after removing LAN noise (mDNS, SSDP, ARP, ssh, port 54915): only IPv6
  neighbour solicitations and one local TCP session
```

**Nothing. The stock stack registered IMS during the window and not one SIP
message crossed an AP-visible interface.**

This is the packet-level counterpart of what
[`../2026-09-06_ut-oracle-ims-state/`](../2026-09-06_ut-oracle-ims-state/) read
from ofono: the IMS connection context is `Active: false` while IMS is
registered. **The modem terminates the IMS PDN internally.** The AP never sees
the traffic, so no capture on the AP can ever show the stock REGISTER.

## ☠️ Two dead instruments before this one measured anything

Both reported **"0 packets"**, which is exactly what the real answer looks like.

1. **tcpdump could not start at all.** `/system/bin/tcpdump` is an Android
   binary; run from the Ubuntu side it dies with *"CANNOT LINK EXECUTABLE …
   library libc.so … not accessible for the namespace (default)"*, and its
   stderr did not reach the log. Two full runs reported zero and meant nothing.
   It has to run **inside the container**: `lxc-attach -n android -- …`.
2. **The first run never triggered a re-registration.** `dbus-send` without
   `--print-reply` returned before ofono acted, so the window held a steady
   registered state and there was nothing to capture.

Both were caught by asking the tool a question with a known answer — five
packets on `wlan0`, where traffic certainly exists — before believing its
silence. **And the final conclusion rests on a third such control**: `tcpdump
-i rmnet_data2` while pinging through it shows the ICMP echo request and reply,
so the capture can see rmnet. Without that, "no SIP on rmnet" would have been
indistinguishable from "tcpdump does not see rmnet".

## What this closes, and what it leaves

**Closed:** the stock REGISTER cannot be captured on the AP. That is the blocker
under #177 ("until a capture of the STOCK stack's REGISTER exists to diff
against") and the same wall #54 and #64 stand at — and it is now known to be a
property of the platform, not of our tooling. The only remaining route to it
would be inside the modem, over DIAG, which is the command wall
[`../../leads/diag-bringup.md`](../../leads/diag-bringup.md) describes.

**Left standing, and strengthened:** the modem's own IMS stack registers on this
network, with no AP-side bearer and no AP-side SIP. Our imsd design — an
AP-visible IMS PDN with a userspace daemon registering over it as an ordinary
host — is not the same thing done differently; it is a different design, and the
one this operator serves successfully is the other one. That makes
[#172](../../leads/ims-missing-ap-half.md), driving the modem's own stack, the
route the evidence supports.
