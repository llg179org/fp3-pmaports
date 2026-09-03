<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# ☠️ The second rehearsal (03:52–05:31) and the defect it exposed: the OCV would have written an **invented 0 mV drift**

This run went **after** item 121's rehearsal, with the `0b311ba` fixes, and
closed with `=== NIGHT COMPLETE ===`. On miniature parameters (3-minute legs,
`alarm=10s`, `RESTMIN=5`) — so **the legs' current is invalid**, and leg 3 was
disturbed by an ssh login as well (the audit said so correctly). Its value is not
in the measurement but in what it revealed about the structure.

## The finding: the tag is destroyed by its own estimator

`ocv()` reads the slope like this:

```sh
set -- $(grep "^$1 " "$D/ocv.txt" | tail -6 | awk '…')
slope=${1:-}; dropped=${2:-0}
```

`set --` **overwrites the positional parameters**, so from that line on `$1` is
**the slope**, not the `start`/`end` tag. The lines that follow still use `$1`:

```sh
first=$(grep "^$1 " "$D/ocv.txt" | head -1 | awk '{print $3}')
last=$(grep  "^$1 " "$D/ocv.txt" | tail -1 | awk '{print $3}')
s "OCV $1 done: ${last}uV, drift over the last 80 s: $(( (last - first) / 1000 )) mV"
```

**Measured on the device, against the real `ocv.txt`, before the measurement
night:**

```
FIXED  -> OCV end done: 4154137uV, drift: -83 mV
BROKEN -> OCV 0.10 done: uV, drift: 0 mV
```

`grep "^0.10 "` matches nothing, so `first` and `last` are **empty**, and busybox
arithmetic reads an empty operand as **0** (checked separately; `set -u` does not
fire, because the variables are set and merely empty). So the run does **not
crash** — which is the bad news.

☠️ **An invented `0 mV drift` reads as a perfectly rested pack.** That is the
worst shape a broken instrument can take: it reports the best possible result
precisely when it **measured nothing**. The raw `ocv.txt` survives, so the
endpoints are recoverable offline — but the run's own verdict is not, and the
night chain depends on exactly that verdict to accept or reject the OCV
endpoints.

**Fix:** `tag=$1` at the top of `ocv()`, and every reference after `set --` moved
to `$tag`. Fixed in `night-run.sh`, syntax-checked with `busybox sh -n`, and
installed on the device (md5 matches the repository).

## What this says about METHOD

The defect was not found by reading code. It was found by **reading the
rehearsal's log before the live run started**. The log did not report an error:
`OCV end slope over the last 5 min:  mV/min ☠️ NOT RESTED` — a blank where a
number belongs, and a condemning verdict that applied *to the blank*. The cause
of the blank slope was a separate defect (the here-doc, `0b311ba`), and once that
was fixed this second one was left behind, which the blank had been hiding.

☠️ **The same family, for the third time in this thread:** the instrument's
lifetime, the instrument's medium, and now the instrument's *label*. All three
failed while producing output that looked acceptable.

## The clean-up before the night

Every file under `/var/log/fp3/night` is written by **append** (`>>`) —
`ocv.txt`, `run.log`, `samples-B.txt`, `mpss-B.txt` — and `ocv.txt` is read back
by the drift calculation with `head -1` / `tail -1`. If the live run started in
the same directory, **the rehearsal's 03:56 opening OCV would have been the
night's start point**, and the 3-minute rehearsal's samples would have been
prepended to every leg.

So the run directory is archived here, and renamed on the device to
`/var/log/fp3/night-rehearsal-20260903-0531`. The live run starts in an empty
directory, from `state=0`, on the built-in defaults: `BOOTS=3`, `LEGMIN=75`,
`RESTMIN=30`, `ALARM=90`, `BAND=eutran-1` — verified that **there is no `conf`
file**, so no miniature parameter can be inherited.
