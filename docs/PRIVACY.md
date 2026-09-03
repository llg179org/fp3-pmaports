<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# Addresses and identifiers in this repository

This repository is public. Anything that identifies the owner's network session,
subscriber account or home network is **masked here and kept only on the owner's
own machine**, outside any repository.

## What is masked

Host addresses appear as `a.b.x.x` — the first two octets are kept so that the
analytically relevant facts survive (private vs public range, two addresses in
different /16s, how many distinct addresses a capture contained), and the host
part is dropped. This covers operator-assigned addresses (P-CSCF, DNS, the
bearer's own address) and the owner's LAN.

Also never committed: IMSI, ICCID, MSISDN (phone numbers), and the IMEI.

## What is NOT masked, and why

- `172.16.42.1` / `172.16.42.2` and `10.42.0.1` — the USB gadget's link-local
  addresses. They are fixed by the gadget driver, identical on every such device,
  and identify nobody. The documented `fp3-ssh` / `ut-ssh` route needs them.
- Vendor version strings that look like addresses. `qcom,gui-version =
  "PMI8998GUI - 2.0.0.54"` in the downstream device tree is a firmware version,
  not an address, and `docs/device_tree/downstream/` is excluded from masking for
  that reason. ☠️ A first pass on 2026-09-03 did rewrite those; it was caught and
  reverted from git before it was committed. A masking rule that matches on shape
  alone will corrupt data — match on shape **and** location.

## Where the real values are

On the owner's machine, outside every repository. The masking pass of 2026-09-03
left its originals under `~/…/fp3-private/`. ☠️ Masking the working tree does not
remove anything from **git history**: values committed before that date are still
reachable in old commits. Rewriting published history is a separate decision and
has not been made.
