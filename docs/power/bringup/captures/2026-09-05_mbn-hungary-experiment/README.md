# #166 — the Hungarian carrier config could not be loaded: qmicli segfaults

**Date:** 2026-09-05, 12:54–13:05 CEST · **Slot:** b (pmOS,
`7.1.3-postmarketos-qcom-msm8953`) · **Card:** dev card `…6542`, One HU
**Result:** the experiment did not run. **The modem is unchanged and needs no
restore** — verified, not assumed.

## What was authorised, and how the bound was respected

The operator granted this window a free hand on 4G calling: anything **reversible**
may be done without asking. A carrier config qualifies, because `pdc` can activate
the previous one back — *but only against a before-state that exists*. So, in
order, before anything was touched:

1. `before-state.txt` — the full `--pdc-list-configs` for both `software` and
   `platform`, 25 software configs, `ROW_Commercial` **Active**;
2. `RESTORE.md` — the exact command to put it back, with the active config's id.

☠️ **That ordering is the whole content of the word "reversible".** A restore path
written afterwards is a belief that one could be reconstructed.

## What it confirmed before it failed

☠️ **The August reading still holds today.** One of the three unverified legs of
the MBN hypothesis was that `ROW_Commercial` Active came from a pmOS capture dated
2026-08-29 and might have changed. Re-read on 2026-09-05:

```
$ qmicli -d qrtr://0 --pdc-list-configs=software
Total configurations: 25
Configuration 1:
    Description: ROW_Commercial
    Status:      Active
```

## Where it stopped

```
$ qmicli -d qrtr://0 --pdc-load-config=/tmp/vfhu.mbn
rc=139          # 128+11 — SIGSEGV
```

Reproducible: two consecutive attempts, both `rc=139`. It is **specific to this
verb** — on the same device, in the same session:

| command | result |
|---|---|
| `--pdc-list-configs=software` | works, 25 configs |
| `--pdc-list-configs=platform` | works |
| `--pdc-noop` | `rc=0` |
| **`--pdc-load-config=<file>`** | **`rc=139`, segfault** |

`qmicli` is **1.39.0**. The file was pushed and md5-verified on both sides
(`e109121124a8a97d353d818fb5c3c883`, 36480 bytes), so it is present and intact;
the verbose run shows the crash comes after CTL negotiation, i.e. client-side.

A search found no public bug report for this verb. libqmi's NEWS carries other
segfault fixes, none of them this one.

## The device is untouched

After both crashes: **25 configs, `ROW_Commercial` still Active.** The load never
reached the modem, so `RESTORE.md` was not needed — but it exists, and it is what
made the attempt permissible in the first place.

## What would unblock it

1. **A different libqmi.** Build another version of `qmicli` and retry — the crash
   is in the tool, not in the modem's answer.
2. **Report it upstream**, with a backtrace. That needs a debug build or a core
   dump, neither of which is set up on the device; it is worth doing because this
   project sends things upstream anyway.
3. ☠️ **Do not conclude the modem refuses the config.** Nothing was sent to it. The
   MBN hypothesis is neither advanced nor damaged by this.
