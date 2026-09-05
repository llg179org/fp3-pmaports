# #157 — what the touch fault rate on r82 actually is, and when it fires

Date: 2026-09-05, boot of 2026-09-05 18:0x (r82, `_commit=3f843d05`, the supply
fix from #155 present). Phone in ordinary use by the operator, on WiFi, USB
unplugged. Kernel journal, not dmesg — the ring buffer had already been
overwritten by the storm below and would have hidden its own beginning.

## The instrument

```sh
journalctl -k -b --no-pager -o short-iso --since '2026-09-05 17:55' \
  | grep -Ei 'himax|qup'
```

28 619 lines. `himax-errors-since-1755.txt` holds all of them with the `-5`
storm collapsed to a count.

## What it says

| when | code | lines | what it was |
|---|---|---|---|
| 18:11:06 – 18:14:09 | `-5` (EIO) | **28 608** | a wedge that lasted ~3 min and ended only when the driver rebound (`input: Himax Touchscreen as …/input7` at 18:14:09) |
| 18:23:54 | `-110` then `-6` | 2 | |
| 18:25:23 | `-110` then `-6` | 2 | |
| 18:27:02 | `-110` then `-6` | 2 | |
| 18:28:56 | `-110` then `-6` | 2 | |
| 18:34:16 | `-110` then `-6` | 2 | |

**Five `-110`/`-6` pairs in eleven minutes, not the three the operator noticed.**
Three of the five (18:27, 18:28, 18:34) were never reported as freezes at all —
which says the operator's report undercounts the fault, it does not bound it.

☠️ The operator also reported a touch dropout at **~18:08**, and there is **no
kernel line for it**. Whatever that was, it was not an i2c failure. It is not
explained by this capture and should not be folded into #142.

## The trigger, for the one case where it can be dated

r82 computes the i2c-qup transfer timeout once at probe as
`TOUT_MIN*HZ + usecs_to_jiffies(MX_DMA_TX_RX_LEN * one_byte_t)` = **14.976 s**
regardless of transfer length, so a `-110` is logged 14.976 s *after* the read
started. The 18:23:54 pair therefore began at **≈18:23:39.0**. (Inference from
the known constant, not a timestamped read start — the driver logs only the
failure.)

At 18:23:38 the modem logged `access technology changed (lte -> gsm, gprs)` and
at 18:23:39 an incoming call went `ringing-in`. That is the same second the read
began. So for this one fault the trigger is the **CS-fallback RAT switch plus
the incoming call**, and it matches the operator's report that an incoming call
froze the touchscreen while they were tapping.

The other four have no call and no RAT change near them, so the call is *a*
trigger, not *the* trigger.

## What follows for #157

Both halves of #157 are justified by this capture and by different lines of it:

- **the i2c-qup timeout** — each `-110` costs 14.976 s of a blocked IRQ handler
  today. Sized from the transfer, the same failure costs ~0.5 s.
- **the himax retry** — the `-6` immediately after each `-110` shows the second
  access fails fast, so a retry is cheap; and the `-5` storm shows what one lost
  release costs (the operator's calculator held a key down through it).
- **the rate limit** — 28 608 lines in 183 s is 156/s, a flash-write and
  log-flood problem of its own, and it is what destroyed the dmesg evidence of
  the storm's start.

## Redaction

The journal lines that date the call carry the calling **MSISDN**. They are not
reproduced here; only the timestamps and the state names are. `tests/no-identifiers.sh`
was run over this directory before it was committed.

## What code this measurement produced

The return direction, so the chain can be walked from either end. Verify a hash
resolves before trusting it (`git -C linux-fp3 rev-parse --verify <hash>^{commit}`);
a list like this rots silently when a branch is rewritten.

| commit | what this capture contributed to it |
|---|---|
| `e79375c44e2f` i2c: qup: size the transfer timeout from the transfer | the 14.976 s each `-110` cost, five times in eleven minutes |
| `c3111d25d687` Input: himax_hx83112b - retry a failed event read, and rate-limit | the 28 608 lines in 183 s, and the lost release that held a calculator key down |
| `e30042e95f60` i2c: qup: report the bus state when a transfer times out | the `-110`/`-6` pairing that made "who held the bus" the unanswered question |
| `3f9efbef5e13` i2c: qup: clear the bus when a transfer times out with it held | the same pairing, once the vendor driver showed the mechanism |
