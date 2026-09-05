# 21:26 — the kernel disabled the touchscreen's interrupt, and the log rate limit is why it got that far

2026-09-05, operator report: *"21:26 durva fagyás"*. Kernel r84 (`#85-fp3`,
`_commit=896aac5ad103`). This is the first **field** fault captured with the new
i2c-qup diagnostics in place, and it is the most informative one so far.

## What happened

```
21:26:19   first  Failed to read input event: -5     (EIO)
21:26:24   himax_handle_input: 43449 callbacks suppressed
21:26:29   himax_handle_input: 42426 callbacks suppressed
21:26:30   last   Failed to read input event: -5
21:26:31   irq 127: nobody cared (try booting with the "irqpoll" option)
21:26:31   Disabling IRQ #127
```

**85 905 failed reads in 11 seconds** (30 printed + 85 875 suppressed) —
about **7800 per second** — and then `note_interrupt()` disabled the
touchscreen's interrupt. The panel was dead until it was rebound by hand;
`/proc/irq/127/spurious` afterwards read `count 0 unhandled 0`, the counters
having been reset by the re-request.

☠️ **No `-110` and no `timed out` line anywhere in the window.** The bus-clear
added in r84 never ran, and cannot help this fault: it is on the `-EIO` path,
where the controller reports an error immediately rather than timing out.

## The cause, in the driver

```c
	error = himax_handle_input(ts);
	if (error)
		return IRQ_NONE;
```

The interrupt *was* ours. `IRQ_NONE` tells the kernel it was not, the line is
level triggered so the controller re-asserts at once, and every pass is counted
as unhandled. At 100 000 of them `note_interrupt()` disables the line. Fixed by
`c59812386d99`, which returns `IRQ_HANDLED`, resets the controller once the
failures look like a wedge, and sleeps between passes if that does not help.

## ☠️ Why this did not happen on r82, and it is not flattering

r82 had the same `IRQ_NONE` bug and never tripped it, because the failure rate
was **156 per second** — every failure printed, and `console=ttyMSM0,115200` is
in the kernel command line. The arithmetic:

```
one line "Himax-hx83112b-TS 2-0048: Failed to read input event: -5"
   + timestamp + newline                              =    72 characters
115200 baud, 8N1                                      = 11520 characters/s
                                                 ->      160 lines/s
r82 measured                                             156 lines/s
```

A 2.5 % match. **The serial console was the brake.** At 156/s the 100 000
threshold needs eleven minutes, and the r82 storm ran three; it ended in a rebind
instead of a disabled IRQ.

The `dev_err_ratelimited` added in `c3111d25d687` removed that brake. It did not
create the bug — the bug is the `IRQ_NONE` — but it released the rate that trips
it, and the visible result for the operator got worse: a dead panel in eleven
seconds instead of a log flood in three minutes.

**The lesson is not "keep the flood".** 28 608 lines to flash, an overwritten
dmesg ring, and a console pacing a kernel error path are all faults. The lesson
is that removing an accidental throttle exposes whatever the throttle was hiding,
and that has to be looked for deliberately rather than discovered by the operator.

## The band-aid running until r85 ships

`fp3-touch-guard.sh`, installed as `/usr/local/bin/fp3-touch-guard` with a
systemd unit, follows the kernel log for `Disabling IRQ #` and rebinds the
touchscreen. Bounded to 6 rebinds per hour, after which it refuses and says so.

☠️ **Remove it when r85 is on the phone.** It papers over the exact fault
`c59812386d99` fixes.

Proved against a known positive before being trusted, rather than after:

```
echo "TEST-ONLY ... Disabling IRQ #127" > /dev/kmsg
  -> fp3-touch-guard: kernel line: TEST-ONLY ... Disabling IRQ #127
  -> fp3-touch-guard: rebound 2-0048 ... (rebind 1/6 this hour)
  -> input13 became input14
```

## Why r85 is not on the phone yet

GitHub is rate-limiting the archive endpoint after four ~250 MB kernel tarballs
today: `wget: server returned error: HTTP/1.1 429 Too Many Requests` during
`pmb checksum`. Not a missing commit — the push output and `git ls-remote` both
show `9c2d03f147c8` on the fork. It needs a retry once the limit clears.
