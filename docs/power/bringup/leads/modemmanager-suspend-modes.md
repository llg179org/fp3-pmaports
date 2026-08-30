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

## Still open

- re-measure the residency front on the **logind** path (running: `terse-ab.sh`,
  which restarts ModemManager per leg so terse cannot carry over);
- price `--test-low-power-suspend-resume` against call delivery — expected to buy
  residency and lose the call, which would disqualify it;
- find out **why terse is not enough on this device** if the re-measurement still
  shows the modem ending logind suspends: terse disables 3GPP unsolicited events,
  but the SMD edge may be rung by something outside that set.
