# The warning fires — so "the modem does not refuse the unregister" is a real negative

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-08-31. Why this was needed: on the same day, a patched ModemManager
reported **no** `<wrn>` across 43 terse applications in the overnight census and
one dedicated suspend, and that was read as *the modem accepts the unregister*.
A logging branch nobody has seen fire cannot support that reading — silence from
a live branch and silence from a dead one look identical.

## Attempt 1 — low power. Failed as a known positive, and said why

[`run1-lowpower.txt`](run1-lowpower.txt). The modem was put in low power
(`--set-power-state-low`, state `disabled`) and a real logind suspend taken.

```
21:07:47  power state updated: low
21:07:52  setting terse state (2/2): all done
```

**No `terse state 3GPP (n/3)` line at all.** On a disabled modem the 3GPP terse
steps are not run, so there is no step that could fail — the method cannot
produce the positive. That was the pre-registered second branch, and it is
distinguishable from a dead branch rather than being confused with it.

☠️ One by-product worth keeping: an unrelated
`<wrn> couldn't reload extended signal information` appeared in the same window,
which proves `mm_obj_warn` reaches the journal at the default log level. A
missing warning is therefore not a log-level artefact.

## Attempt 2 — and the positive arrived from an unplanned direction

[`run2-injected.txt`](run2-injected.txt). A build with a forced failure in the
disable path was prepared and installed for one suspend. The injected failure
itself was never exercised — 25 s after the restart the modem had not re-probed
far enough for the 3GPP step to run. But stopping the daemon to swap the binary
produced the real thing:

```
21:16:19 [47379] <wrn> [modem0] couldn't unregister serving system indications:
         'Cannot write message: Error sending data: Broken pipe';
         the modem may keep sending them
```

That is the **unmodified patched build** (`ed056596`), the exact text the patch
adds, at default log level, carrying the underlying error verbatim — a genuine
failure (the QMI socket went away during shutdown) rather than an injected one.

⇒ **The branch fires.** Today's negative is a measurement, not a silence:
across 43 terse applications and a dedicated suspend the modem answered every
unregister without an error, and the instrument that would have said otherwise
has now been seen saying it.

## What this does not license

- It shows the branch reachable and the message correct. It does **not** show
  that a *modem-side refusal* specifically produces it — the observed failure was
  a transport error, one layer below.
- The forced-failure build was never actually exercised, so the injection is
  unproven and was removed from the device rather than left as a trap.

## State afterwards, verified rather than assumed

`/usr/sbin/ModemManager` is `ed056596` — the normal patched build, matching the
host copy; ModemManager `active`; modem `registered`; and the distribution's own
binary is still at `/usr/sbin/ModemManager.pkg.bak`, one `mv` from restoring.
