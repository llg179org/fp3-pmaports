# Status — where the port stands right now

> ⚠️ **AI-generated.** This page was written by Claude working under the
> direction of Lajosházi, László Gergely, who reviewed every change and made or
> reviewed every measurement it rests on.

**This file is the live one.** It is rewritten as work happens, not at the end of
a session, and it is the first thing to read when picking the work back up. The
reasoning behind each open item is in [`TODO.md`](TODO.md) (by item) and
[`FP3-TODO.md`](FP3-TODO.md) (by branch); closed items move verbatim to
[`TODO-DONE.md`](TODO-DONE.md). When this page and `TODO.md` disagree, **this one
is newer and `TODO.md` is more complete** — fix whichever is wrong rather than
picking a winner.

☠️ Every line below is the kind that goes stale first. Each row says how to read
it off the device instead of trusting it.

Last updated: **2026-08-23 14:30**.

## The device

| what | value | how to check |
|---|---|---|
| kernel package | `linux-fp3-7.1.3-r71` | `apk info -vv \| grep ^linux-fp3` |
| build stamp | `#72-fp3` | `uname -v` |
| pinned commit | `debug-int/7.1.3` `b5ae3e0f` | `grep _commit linux-fp3/APKBUILD` |
| boot config | 3 labels, md5 `863cdf20…`, `panic=10`, `timeout 3` | `md5sum /boot/extlinux/extlinux.conf` |
| last full battery | **31 ok / 0 failed / 3 skipped** (2026-08-23 13:43) | `tests/fp3-selftest` |

The three extlinux labels are `postmarketOS` (default), `postmarketOS-fallback`
(an older kernel, kept as the safety net) and `postmarketOS-xo` (adds
`clk_smd_rpm.xo_sleep_off=1` for the deep-sleep experiments).

## Branch tips

| branch | tip | note |
|---|---|---|
| `wip/7.1.3/audio` | `2f4ea47a` | the two SLIMbus codec fixes on top |
| `integration/7.1.3` | `f6f9ea02` | cherry-pick sum, debug-free |
| `debug-int/7.1.3` | `b5ae3e0f` | **what the package builds** |
| `wip/7.1.3/power` | `d0e738c1` | smd wakeup teardown fix |

`fp3-pmaports` `origin/main` carries the docs and the APKBUILD; the kernel goes
to remote `fork` only, over port 443, and never to `origin`.

## The work queue, in order

Everything here is machine-doable unless the row says otherwise. Work down the
list; do not stop at the end of an item to report.

1. **Diagnose why the WCD9335 does not survive an ADSP restart** (`TODO.md`
   defect 3, `FP3-TODO.md` item 41). This is the functional root cause, and it
   is now reproducible: restart the ADSP, addressed **by name**, and the burst
   follows. It is also the only reproduction bed for proving the two fixes that
   are in but unproven.
2. **Read the RPM `Client Votes` mask immediately after a suspend window**, from
   the `postmarketOS-xo` label — the one boot where the APSS actually goes down
   during the window. Last open leg of `TODO.md` item ②.
3. **Price the WiFi lever in mA** (slope leg, `wlan0` down vs up). ☠️ PRONTO
   parks holding the XO when `wlan0` is down, so the naive reading flatters it.
4. **Housekeeping:** `linux-postmarketos-qcom-msm8953-7.1.3-r0` is installed,
   owns no `/boot/vmlinuz`, and makes every `apk` run end with `only one kernel
   release/flavor is supported`.
5. **Measure whether `base_dir` fixes the kernel ccache hit rate.** The source
   path carries the commit hash, so every bump is a new absolute path and
   direct-mode hits are expected to miss; `base_dir` is empty. The test is one
   file compiled from two directory names around a `ccache -z`, then the next
   real bump's wall-clock.

**Waiting on a human, skip over them:**

- the call-wake ↔ deep-sleep trade has to be *decided* (inhibitor while ringing,
  or conditional arming), not measured further
- the wake-arm unit's default, the WiFi suspend policy, and the fate of the three
  experiment knobs (`clk_smd_rpm.xo_sleep_off`, `qcom_smd_regulator.both_sets`,
  `icc_smd_rpm.sleep_init` — all default OFF)
- the USB-detached combined session (rail census, slot switch to the UT oracle)
- sending `smd-wake-v1` to the LKML

## Guardrails that have each cost a day

- **The category rule.** A kernel change lands on `wip/<base>/<category>` **and**
  `integration/<base>` **and** `debug-int/<base>`, then all of them are pushed to
  `fork`, and only then does `_commit` move.
- **Tarball check before the build:** `curl -sL -o /dev/null -w '%{http_code}'`
  on the pinned commit must be **200**, and the same command on a bogus hash must
  be **404** — a verifier not yet shown failing has proved nothing.
- **`apk add` first with `--simulate`,** read the output for `Purging`.
- **`apk add` rewrites `extlinux.conf`.** Re-arm it afterwards and check the md5;
  the backups live next to it in `/boot/extlinux/`.
- **One `pmbootstrap` command at a time.**
- **A reboot is witnessed by `uptime`, never by a return code.** Use
  `systemctl reboot`; a backgrounded `reboot` over ssh dies with the session.
- ☠️ **remoteproc indices move between boots.** Address by name or platform
  address (`grep -l 4080000 /sys/class/remoteproc/*/name`), never by index.
- ☠️ **Never run two destructive measurements at once**, and never trust a
  waiter built on `pgrep -f` — it matches its own command line and never exits.
