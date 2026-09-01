# ★★★★★ The duty step is bracketed in the journal — and every later "MM stopped" arm was measured after ModemManager had already configured the modem

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01. Read from the device's own journal, which is **persistent**
(`/var/log/journal`); boot `-1` covers 2026-08-30 14:00:30 → 2026-09-01 11:56:45,
so the whole window survived the reboot of 11:56.

## The question

The MPSS duty was **4.9–5.1 %** on 2026-08-31 between 05:38 and 06:12 (four
measurements: legs A, B, A′ of
[`../2026-08-31_mm-duty-ab/`](../2026-08-31_mm-duty-ab/README.md) plus the 05:52
sleep window) and **33.6 %** by 11:48 the same day, where it has stayed through
every configuration since. What happened in between?

## What the journal says

Four lines out of the 186 in that six-hour window carry it:

```
Aug 31 06:00:21 fp3 gnome-calls[2995]: ModemManager vanished from D-Bus
Aug 31 11:08:17 fp3 [47307]: fp3 : COMMAND=/usr/bin/sh -c ... cp /tmp/ModemManager.new $MM ...
Aug 31 11:08:26 fp3 [47337]: fp3 : COMMAND=/usr/bin/sh -c systemctl start ModemManager; ...
Aug 31 11:08:28 fp3 gnome-calls[2995]: ModemManager appeared on D-Bus
```

⇒ **ModemManager did not run at all between 06:00:21 and 11:08:28.** At 11:08:17
the locally built binary (upstream `5e91dd2` plus the three
`qmi-report-failed-unregister` patches) replaced the packaged one, and it was
started eleven seconds later. The next duty measurement, at 11:48, read 33.6 %.

The step is bracketed to **06:00–11:08**, and the only deliberate act inside that
bracket is the binary swap and restart at 11:08.

## ☠️ And the part that invalidates how I read every later arm

Every "ModemManager stopped" arm run since — the 47-round control, the Wi-Fi arm,
the cable-in arm, the modem-core-cycle arm, the post-reboot ladder — was started
by `modem-night.sh`, which **gates on the modem reading `registered` and only
then stops the daemon**. Reaching `registered` requires ModemManager. So in all
of them **the daemon had already run and configured the modem before the window
opened**.

That is why nothing moved, and it is also why the reboot did not help: at boot
ModemManager starts again and does the same thing. "MM stopped" in those captures
means *stopped after configuring*, not *never ran* — and the difference is the
whole question.

☠️ The 5 % readings are the only ones taken in a state where the current
ModemManager had **not** configured the modem: leg B at ~05:50 ran the *packaged*
binary, and legs A/A′ plus the 05:52 window ran with the daemon stopped after
only that binary had touched the modem.

## ☠️ What this does not establish

The binary swap is a **coincidence in time**, not a demonstrated cause, and one
number argues against it: on 2026-08-29 the same stack with the **packaged**
binary measured **48.9–52.7 %** on this cell
([`../../leads/modem-carrier-config.md`](../../leads/modem-carrier-config.md)).
So the packaged ModemManager has produced both ~50 % and ~5 %, and the new one
~34 %. **Three regimes, two binaries** — the binary alone does not explain it.

The test is cheap and reversible: `/usr/sbin/ModemManager.pkg.bak` is one `mv`
away, and the packaged binary can be put back and the same arm re-run.

## Raw

The 186-line window was extracted on the device as `/tmp/win.txt` with

```sh
journalctl -b -1 --since "2026-08-31 06:00" --until "2026-08-31 12:00" --no-pager
```

and is in [`raw/journal-window-2026-08-31_06-00_11-08.txt`](raw/journal-window-2026-08-31_06-00_11-08.txt).
The four lines quoted above are verbatim from it.

## Addendum, 2026-09-01 20:40 — the run-up to the cheap window, and why it can no longer be read

The outside review asked one more thing of this journal: **how long had the radio
been left undisturbed before 05:38**, since a backoff that grows would predict a
long quiet stretch ahead of a cheap window.

**Partly answerable, from what was already captured:**

- the cheap legs ran on **one boot, at uptime 16 h**
  ([`../2026-08-31_mm-duty-ab/`](../2026-08-31_mm-duty-ab/README.md)), so the
  modem had been up since roughly 2026-08-30 13:40 without a firmware reload;
- **ModemManager was running for leg B** at ~05:55 and the duty was **4.9 %** —
  so the cheap state is not "the daemon was off", and the 06:00:21 D-Bus
  disappearance is the A′ leg's own `systemctl stop`, not an unexplained event.

**Not answerable, and it never will be:** what the radio did before 05:38. The
extract in `raw/` starts at 06:00 because that is where the question stood when
it was taken.

### ☠️ The journal is not an evidence store on this device, and this capture's own header is now wrong

The header above says the journal is persistent (`/var/log/journal`) and that
boot `-1` covered 2026-08-30 14:00:30 → 2026-09-01 11:56:45. The directory is
still there and journald still writes to it. But measured tonight:

```
$ journalctl --list-boots
IDX BOOT ID                          FIRST ENTRY                  LAST ENTRY
  0 ab239ffe...                      Tue 2026-09-01 17:10:52 CEST Tue 2026-09-01 20:27:09 CEST
$ journalctl --disk-usage
Archived and active journals take up 21.5M in the file system.
```

**One boot. Nothing before 17:10 today.** Every earlier boot — including the one
this capture reads — has been discarded, and 21.5 MB is all journald is keeping.

The mechanism is not a mystery and it is not a mistake anyone made: `/` is a
2.4 G filesystem at **85 %**, with ~330 MB free. journald's default
`SystemKeepFree` is **15 % of the filesystem** (~360 MB), so the free space is
*below* the floor journald is trying to preserve — and it responds by rotating
history away continuously, whatever `SystemMaxUse` would otherwise allow.

Two consequences, both operational:

1. **A journal line is evidence only until the next rotation.** The standing note
   "do not vacuum the journal, it is evidence" was written to protect exactly
   this window, and the window evaporated anyway, without anyone vacuuming
   anything. Anything wanted from the journal must be **extracted to the repo the
   same day**, and the extract must be wider than the question that prompted it —
   this one was cut at 06:00 and the run-up is gone with it.
2. **Free space on `/` is a measurement resource**, not just a build concern.
   Below ~15 % the device silently stops keeping its own history.
