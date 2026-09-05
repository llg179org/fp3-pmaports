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

Also never committed: IMSI, ICCID, MSISDN (phone numbers), the IMEI, and the
MAC address of any access point or of the phone's own wlan interface.

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

## The check that enforces this

```sh
sh tests/no-identifiers.sh              # scan the working tree, before committing a capture
sh tests/no-identifiers.sh --self-test  # prove it still catches a planted identifier
```

☠️ **The rule above was written on 2026-09-03 and was already being broken when it
was written.** An audit on 2026-09-05 found the IMEI in four files, both SIM cards'
IMSI and ICCID, a caller's number in two capture journals, and - not covered by
this page at all - the home access point's BSSID together with the phone's own
wlan MAC, pasted in with a dmesg block where nobody would look. A BSSID is a
premises identifier: public databases map it to a location.

☠️ **And the first version of the check reported clean while a phone number sat in
the tree.** The file holding it has two NUL bytes, so `grep` treated it as binary
and skipped it silently. `grep -a` is the fix and the self-test now plants an
MSISDN behind a NUL byte. A checking tool that has only ever been seen saying
"clean" has proved nothing.

## The 2026-09-05 history rewrite

The identifiers listed above had been committed since 2026-08-20, so masking the
working tree was not enough and the published history was rewritten with
`git-filter-repo`. All 1262 commits keep their content and order; every hash from
the first affected commit onward changed. A fresh clone from GitHub was then
scanned blob by blob and is clean.

Three things worth keeping from how it went:

- ☠️ **`--replace-text` silently skips blobs it considers binary** — the same
  blind spot as `grep` without `-a`, and it left exactly the file that had hidden
  a phone number from the first scan. A second pass with `--blob-callback`, which
  makes no such distinction, was needed. Verify after filtering; do not assume.
- **The verifier was run against the pre-rewrite backup first**, where it found
  all ten identifier classes, before being trusted on the rewritten repo where it
  found none. A check only seen saying "clean" has proved nothing.
- **The old tip was deliberately NOT tagged and pushed.** The project's usual rule
  is to tag before a force-push so the previous tip stays reachable; here that
  would have kept alive precisely what was being removed. The backup is a
  `git bundle` on the owner's machine under `/mnt/1TB/pmos/fp3-backups/`, outside
  every repository — which is where this page already says the real values belong.

⚠️ **A rewrite does not scrub the forge immediately.** GitHub can still serve an
orphaned commit by its full SHA until it garbage-collects, and forks or caches may
retain it. If that matters, ask GitHub Support to run gc on the repository.

## Where the real values are

On the owner's machine, outside every repository. The masking pass of 2026-09-03
left its originals under `~/…/fp3-private/`. ☠️ Masking the working tree does not
remove anything from **git history**: values committed before that date are still
reachable in old commits. Rewriting published history is a separate decision and
has not been made.
