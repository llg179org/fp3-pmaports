# ModemManager's three suspend modes — and the one nobody read

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every measurement it rests on.

**Why this page exists.** Two days of measurement went into "why does the modem
end every suspend", and the answer was in ModemManager's own source, in a string
that says it outright. It cost the time because nobody read the code behind the
command-line switch the distribution had already set for us. The lead is written
up here **with the reading method that would have found it**, because that method
is the transferable part.

## What the three modes actually do

`src/main.c` wires one of three pairs of callbacks to logind's sleep signal
(`ModemManager 1.25.95`, checkout `306f625`):

| mode | on sleep | on resume |
|---|---|---|
| default (no switch) | `CLEANUP_REMOVE` — remove the devices entirely | re-scan |
| `--test-quick-suspend-resume` | **`CLEANUP_TERSE`** — *"setting modem in terse mode... (only send important signals (call/text))"* | `mm_base_manager_sync` |
| `--test-low-power-suspend-resume` | `CLEANUP_DISABLE \| CLEANUP_LOW_POWER` (`\| REMOVE` in the non-quick pairing) | as above |

`TERSE` is not "do nothing", which is how the quick mode was read here for two
days. It walks `mm_iface_modem_3gpp_terse` → **disable unsolicited registration
events** → **disable unsolicited events**, i.e. it tells the modem to stop
signalling everything except what a call or a text needs. On this device that is
precisely the difference between a suspend that holds and one the modem's SMD
edge ends within seconds.

★ It also means **the lever we were about to reach for is the wrong one.**
`--test-low-power-suspend-resume` disables the modem and puts it in low power; a
radio in low power does not deliver a call, and the target is parity *at the
oracle's responsiveness*. `TERSE` is the mode that keeps the call path and quiets
the rest — and pmOS already ships it.

## ☠️ The trap that made this invisible for two days

**Terse is applied on logind's sleep signal and undone on logind's resume
signal.** Every instrument built here suspends with `rtcwake -m mem`, which writes
`/sys/power/state` directly and never reaches logind — so:

- an `rtcwake` leg **never gets terse applied**; and
- an `rtcwake` leg that follows a logind leg **inherits the previous leg's terse
  state**, because nothing tells ModemManager to undo it.

That second half produced a wrong conclusion from correct data: an A-B-A-B with
`rtcwake` / logind / `rtcwake` / logind slept 82 / 242 / 241 / 242 s of a 240 s
alarm and was written up as "the two paths are equivalent". They are not — the
third leg was still terse from the second. The honest reading is the **first**
leg against the second, and ten consecutive `rtcwake` cycles taken after the last
logind *resume* had cleared terse, which slept 22 / 1 / 5 / 20 / 1 / 5 / 6 / 1 /
6 / 2 s, every one of them ended by the modem edge.

⇒ **Every residency figure measured with `rtcwake` describes the non-terse state**,
which is not the state the phone is in when a real suspend happens (gsd-power and
`IdleAction` both go through logind). They are all owed a re-measurement, and the
error is in the *pessimistic* direction.

The general form, and it is a new safety rule for the instrument set:
**a system-state change applied by a daemon on a D-Bus signal does not happen when
you bypass the bus, and it does not un-happen either.** A knob with sticky state
makes leg order a confound. Restart the daemon between legs, or measure the state
directly, rather than assuming each leg starts clean.

## How to read the journal for it

Terse logs at `mm_obj_msg` level, so it is visible without debug logging:

```sh
journalctl -u ModemManager | grep -i terse
#   terse state 3GPP (1/3): disable unsolicited registration events done
#   terse state 3GPP (2/3): disable unsolicited events done
#   setting terse state (2/2): all done
journalctl -u ModemManager | grep sleep-monitor   # was the daemon told at all?
systemctl show ModemManager -p ExecStart --value  # which mode is live
```

## The reading method this is a lesson in

The switch was set by a **distribution drop-in**, not by us:

```
/usr/lib/systemd/system/ModemManager.service.d/quick-suspend-resume.conf
  owner: postmarketos-base-ui-modemmanager-systemd
```

That is the second time a pmOS quirk silently settled a performance question here
— the first was `GSK_RENDERER=cairo`, which put every GTK4 app into software
rendering and was read for weeks as a camera pipeline problem. **The highest-yield
reading is therefore not upstream documentation but what the distribution
configures on our behalf**, because it is invisible in both the upstream docs and
our own tree. The sweep that finds it:

```sh
# every drop-in on the device, with the package that owns it
for d in /usr/lib/systemd/system/*.d /usr/lib/systemd/user/*.d; do
  for f in "$d"/*.conf; do
    echo "--- $f  [$(apk info -W "$f" 2>/dev/null | sed 's/.*owned by //')]"
    grep -vE '^\s*(#|$)' "$f"
  done
done
grep -rhvE '^\s*(#|$)' /etc/systemd/logind.conf /usr/lib/systemd/sleep.conf.d/*.conf
cat /sys/power/mem_sleep          # s2idle vs deep — this device has s2idle only
apk info | grep -E '^(postmarketos|device-|msm-)'   # the quirk packages
```

And when a switch turns up that way, **read the code behind it, not its help
string**. `--test-quick-suspend-resume`'s help text is *"Enable quick
suspend/resume support for modems which stay on during host suspension"* — which
is true and tells you nothing about `TERSE`. Twelve lines of `src/main.c` did.
Clone the source rather than fetching pages: the upstream GitLab is behind an
anti-bot wall that returns an access-denied page to a fetcher, so
`git clone --depth 200 --filter=blob:none <repo>` is both faster and greppable.

## ✅ Measured: terse keeps the call. The "buys nothing" half is now withdrawn

> ☠️ **2026-08-30 midday — the residency half of this section is not a result,
> because the effect it looked for is an order of magnitude smaller than a
> confound nobody had noticed.** The same configuration produced 52–63 s sleeps
> that morning and **601 / 601 / 600 / 601 s** at midday, the latter four all
> ended by the RTC rather than by the modem
> (`captures/2026-08-30_spread/`). Whatever separates those two regimes is worth
> ~10×; terse was being credited or debited with a few tens of seconds inside
> that. **Every terse comparison on this page and in the captures it cites was
> taken without knowing which regime it ran in**, so none of them can carry a
> residency verdict either way.
>
> The call half stands. It is a one-second coincidence between two logs, not a
> difference between two averages, so the regime cannot touch it.
>
> **What a real terse residency measurement now requires**, and none of the
> earlier ones had any of it: `tools/radio-context.sh` at the head and tail of
> every leg, so the regime is on the record rather than inferred afterwards; a
> return leg (A‑B‑A′), because the day has already produced two "results" that
> were drift; and both legs inside **one** regime, which means checking A before
> trusting B rather than discovering the regime in the numbers.


Both halves are settled, and the residency half retracts what this page said
when it was written (`captures/2026-08-30_terse-call/`):

- **the call survives terse.** One second wide: terse applied at 07:17:04 (four
  journal lines), asleep 07:17:04→07:17:19 by the kernel's own marks, and
  `call state changed: unknown -> ringing-in` at 07:17:19. `TERSE` does not cost
  the call path, so the distribution's default is right on this axis and
  `--test-low-power-suspend-resume` stays disqualified;
- ☠️ **terse buys no residency.** Six legs alternating the two paths with a
  ModemManager restart before each slept **52 / 61 / 62 / 61 / 63 / 63 s** — the
  same with terse as without. The "63 s vs 305 s" contrast on which this page was
  originally written was an instrument artefact: `systemctl suspend` does not
  block, so the script sat for `alarm + 5` seconds and printed that as the sleep.
  Its own output said so — `wake_irq` was the modem edge on legs where no RTC
  alarm had been armed.

⇒ **terse is harmless and useless here**, and the modem-duty front stays open.
The measure that settles it, and which no script bug can forge, is the kernel's
own `PM: suspend entry (s2idle)` / `PM: suspend exit` pair; the host's USB
disconnect/reconnect log is the second, independent witness and touches nothing
on the phone.

## Still open

- **why terse is not enough**: it disables the 3GPP unsolicited events, and the
  SMD edge is evidently rung by something outside that set. Naming that something
  is the open question on the modem-duty front — a per-channel or per-port census
  across a suspend is the instrument;
- **why the same phone slept 240 s at 05:00 and 60 s between 06:00 and 07:00.**
  The wake source is the modem edge in both regimes, so the difference is a state,
  not a mechanism. Naming the state may be cheaper than naming the mechanism.

## ☠️ "terse done" is not evidence that anything was unregistered

Read in ModemManager `306f625` (2026-08-17), which is the tree this device runs.
Not measured — this is a source claim about what the log can and cannot report,
and it matters because the measurement already contradicts the log.

**What terse is supposed to do.** `MM_BASE_MANAGER_CLEANUP_TERSE`
(`src/main.c:98`) runs the 3GPP terse steps
(`src/mm-iface-modem-3gpp.c:3450`): disable unsolicited *registration* events,
then disable unsolicited events. On a QMI modem those reach
`mm-broadband-modem-qmi.c` and unregister a specific list —
NAS `serving_system_events` (`:4334`), NAS `system_info` (`:4388`), NAS
`network_reject_information` (both), and, when `dsd_supported`, the DSD
`System Status Change` indication (`:4369`) — plus, on the other step, the
signal-info config and the WDS data-system-status.

**So the measured noise is precisely what terse claims to remove.** The
2026-08-30 census under terse still saw NAS (port 40) and DSD (port 52)
indications, in a round where the journal carried the terse lines. Those two
statements cannot both describe a working unregister.

**And the journal cannot arbitrate, because it is built not to.** Three
properties, all in the code:

- every one of those completion handlers ends `/* Just ignore errors for now */`
  followed by `g_task_return_boolean (task, TRUE)` (`:4293`, `:4321`) — the step
  reports success whatever the modem answered;
- the failure messages are `mm_obj_dbg`, i.e. **invisible at the default log
  level**;
- ☠️ and on the *disable* path they are not merely invisible, they are not
  emitted at all: both sites guard the message with `if (ctx->enable)`
  (`:4262`, `:4316`), so a failed **un**register logs nothing even at debug.

The consequence is the whole reason this section exists: **the "terse state 3GPP
… done" line in the journal is a statement that the step ran, not that the modem
obeyed.** It is a witness that cannot say no, and reading it as confirmation is
the same error as trusting a `grep` that was never validated against a known
positive.

### What to run, in order

1. `mmcli --set-logging=debug` (or start MM with `--log-level=DEBUG`) across a
   terse suspend, then `grep -i "couldn't register"` the journal. A hit names
   the failing unregister outright. ☠️ A miss is **not** a pass — on the disable
   path the message is suppressed by `if (ctx->enable)` — so this can only
   confirm, never clear.
2. `tools/wake-qmi.sh`, which does not depend on MM's self-report at all: if
   NAS/DSD indications keep arriving under terse, the unregister did not take,
   whatever the journal says. That is the instrument that can say no.
