# r85 on the phone: the IRQ_NONE fix, and the band-aid removed

2026-09-06 00:34–00:49. `#86-fp3`, `_commit=9c2d03f147c8`, package
`linux-fp3-7.1.3-r85`.

## What shipped

`c59812386d99` — `himax_irq_handler` returns `IRQ_HANDLED` on a failed read
instead of `IRQ_NONE`, counts consecutive failures, resets the controller at 10
and sleeps between passes past 30. This is the fix for the 21:26 fault of
2026-09-05, where 85 905 unhandled passes in eleven seconds made
`note_interrupt()` disable IRQ 127 and leave a dead panel.

Also carried: `a268f0d4ccdc`, which makes a failed bus-clear name the condition
that never cleared.

## Verified on the shipped artifact, not on the source tree

☠️ The first check looked for the new string in the extracted `vmlinux` and found
**zero**. That is not absence: `himax_hx83112b` is a **module**, `i2c-qup` is
built in, so only the latter's strings are in the kernel image. Checked in the
right object, with both controls:

| | r85 | r84 | nonsense control |
|---|---|---|---|
| `consecutive failed reads, resetting` in `himax_hx83112b.ko` | **1** | 0 | 0 |
| `bus still held after %d bus-clear attempts: ` in `vmlinux` | 1 | — | 0 |

And on the running phone, against the module `modinfo -n` actually resolves:
present 1, control 0.

## Selftest

`01-identity`, `02-boot-fallback`, `05-modules`, `06-dtb` all PASS —
build stamp `#86-fp3`, package r85, source commit `9c2d03f147c8`, booted DTB
byte-identical to the package's, three boot labels each carrying `panic=`,
watchdog active. `59-touch-i2c-stall` correctly SKIPs: zero active minutes.

## The band-aid is gone

`fp3-touch-guard.service` disabled and both files removed in the same run that
installed r85 — it papered over exactly what `c59812386d99` fixes, and leaving it
would have hidden whether the fix works.

## Housekeeping that mattered

☠️ `/` was at **91 %, 196 MB free**, of which **176 MB was `/var/cache/apk`**.
Safety rule 9 is that a full rootfs turns into a reboot loop, and four kernel
installs in a day is exactly how it fills. Cleared the cache (nothing there is
needed to boot; apk refetches), now **84 %, 372 MB free**. `/boot` also pruned:
r82's kernel and DTB removed after checking `extlinux.conf` no longer names them.

## Still open

The fix is **deployed and verified as an artifact**, not as a behaviour. Nothing
has exercised it: 0 active minutes since boot. It needs a real `-EIO` storm to
prove that the IRQ survives, and that needs the phone used.
