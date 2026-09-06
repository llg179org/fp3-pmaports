# Loading the Vodafone Hungary (One) carrier config onto the modem

**2026-09-06**, pmOS on slot b, kernel r88 (`6113869dcc3d`), modem firmware as
shipped. SIM: dev card, ICCID …6542, **One Hungary, MCC 216 MNC 070** — the
network formerly branded Vodafone Hungary, which is why the Vodafone Hungary MBN
is the matching config and not a foreign one.

Prior state, and the mistake this replaces, are in
[`2026-09-06_carrier-config-volte/`](../2026-09-06_carrier-config-volte/): the
modem shipped with `ROW_Commercial` active, and an earlier attempt activated
`Global-VoLTE-Vodafone`, a Vodafone **Germany** test-network config that the
repo explicitly says not to reach for.

## Where the config came from

The Ubuntu Touch slot carries the stock Fairphone firmware image, and its
`firmware_mnt` holds the full per-carrier MBN set:

```sh
ut-ssh 'cat /android/vendor/firmware_mnt/image/modem_pr/mcfg/configs/mcfg_sw/generic/eu/vodafone/commerci/hungary/mcfg_sw.mbn' > hu.mbn
```

36 480 bytes, md5 `e109121124a8a97d353d818fb5c3c883`, sha1
`974aff0305feca72c3573135709fa82cbb066ea0`. Identity checked before loading
anything: `MCFG` magic at offset 8192, and `strings` gives `VDF_Hungary`,
`Vodafone_Hungary_Commercial`, `internet.vodafone.net`.

**The modem does not ship with it.** Its PDC store held 25 software configs
including seven `*-VoLTE-Vodafone` ones (UK, Spain, Netherlands, Italy, IE,
Global, Germany) and a `Non_VoLTE-Vodafone` — but no Hungarian entry. That is
the whole reason for this exercise.

## ☠️ `qmicli --pdc-load-config` segfaults before sending a single byte

```
[qrtr://0] registered 'pdc' (version unknown) client with ID '1'
Loading config asynchronously...Segmentation fault (core dumped)
```

Measured with qmicli 1.39.0 / `libqmi-1.38.0_git20260414-r0` on this device. It
is a **client-side bug**, not a modem or a config problem: the crash happens in
`load_config_file_from_string()`, before the first chunk exists — note that the
`Uploaded 0 of 36480` line the chunk builder prints never appears.

`src/qmicli/qmicli-pdc.c`:

```c
file_contents = (guchar *) g_mapped_file_get_contents (mapped_file);
...
g_checksum_update (checksum, file_contents, file_size);
g_free (file_contents);          /* mmap region owned by the GMappedFile */
```

`g_mapped_file_get_contents()` returns a pointer into the mmap'd region owned by
the `GMappedFile`; `g_free()` on it is an invalid free. The mapping is still
needed afterwards — `load_config_input_create_chunk()` calls
`g_mapped_file_get_contents()` again for every chunk — so the free is not merely
early, it is wrong outright.

**Do not conclude from this crash that the config, the file or the modem is
bad.** Three separate load attempts were spent before the trace was read closely
enough to see that nothing had reached the modem.

## The way round it: `tools/pdc-load.py`

The same protocol, driven from Python through the `Qmi` and `Qrtr` GObject
introspection typelibs, which are installed on the device — so no rebuild of
libqmi is needed:

```sh
sudo -n python3 pdc-load.py qrtr://0 /tmp/hu.mbn
```

☠️ A `qrtr://` URI is **not** resolved through GIO. `Gio.File.new_for_commandline_arg()`
on it yields something `qmi_device_open()` rejects with *"Cannot open device file
'qrtr://0': No such file or directory"*. qmicli resolves it through the QRTR bus
instead, and so must any reimplementation: `Qrtr.get_node_for_uri()` →
`Qrtr.Bus.new()` → `bus.peek_node(id)` → `Qmi.Device.new_from_node()`.

Progress is reported by the modem, not by the tool — each `load-config`
indication carries the bytes it still expects:

```
uploading 0..1024 of 36480
modem wants 35456 more bytes
...
uploading 35840..36480 of 36480
OK: finished loading, modem reports 0 bytes remaining
```

That countdown is the useful part: it decrements by exactly the chunk size on
every round, so it is independent evidence that bytes really arrived, rather
than the tool's own claim of success.

## What the modem shows afterwards

Judged with a **different** instrument — `qmicli --pdc-list-configs=software`,
already proven working on this device — not with the loader's own verdict:

```
Description: Vodafone_Hungary_Commercial
ID:          97:4A:FF:03:05:FE:CA:72:C3:57:31:35:70:9F:A8:2C:BB:06:6E:A0
```

The config **ID is the SHA1 of the file**, which is how a load can be confirmed
without trusting the loader.

☠️ **The list stayed at 25 entries.** The store is full at 25 software configs
and the load **evicted** one — `TIM_Italy_Commercial` is gone. So a count is not
a witness that a load happened; the description or the ID is. And a config you
still want can disappear because you loaded another one.

## Revert path

`ROW_Commercial`, ID `5CF9CADA5C358517BA3BB888D0342B79BD5FADED` — the config
that was active before any of this:

```sh
sudo -n qmicli -d qrtr://0 --pdc-activate-config=software,5CF9CADA5C358517BA3BB888D0342B79BD5FADED
```

## Activation, and what it changed

```sh
sudo -n qmicli -d qrtr://0 --pdc-activate-config=software,974AFF0305FECA72C3573135709FA82CBB066EA0
```

*"Successfully requested config activation"*, returned in under a second — the
warning elsewhere in these notes that a PDC activate can take minutes did not
apply here. The modem was then cycled (`mmcli -m any --disable`,
`--set-power-state-low`, `--set-power-state-on`, `--enable`); ☠️ every `mmcli`
call must use `-m any`, because the modem renumbers across a restart and a
hardcoded `-m 0` silently fails on every line while the script reports progress.

Afterwards, read back with `--pdc-list-configs=software`:

```
Description: Vodafone_Hungary_Commercial
Type:        software
Size:        36480
Status:      Active
```

and the modem came back on the network with no regression:

```
access tech: lte
operator name: vodafone HU
registration: home
packet service state: attached
```

That is the load and the activation, which is what was asked for. Whether it
changes call behaviour is a separate measurement and is recorded below.

## ☠️ I "discovered" our own switch — the correction

Immediately after the activation, an IMS-settings read on the device returned:

```
IMS services enabled setting
  IMS registration service     <not in message>
  voice (VoLTE)                False
  video telephony              False
  voice over WiFi              False
  UT (supplementary services)  False
  SMS over IMS                 False
  USSD over IMS                False
```

**This was first written up as a finding — "the modem had VoLTE switched off in
its own settings, which explains the CSFB fallback". That claim is wrong and is
kept here so the mistake is not repeated.** That vector is *this port's own*
IMS-off state, asserted deliberately for power. The `off` vector is recorded
verbatim in
[`2026-09-05_118-night-triage/run.log`](../2026-09-05_118-night-triage/run.log)
as `vector verified off: voice=False VoWiFi=False video=telephony SMS=False
UT=False` — field for field what was read here.

What holds it there is a unit on the device:

```
fp3-ims-reconcile.timer    OnBootSec=90s, OnUnitActiveSec=5min
fp3-ims-reconcile.service  ExecStart=/usr/local/bin/fp3-ims-reconcile.py off
                           "Hold the modem's IMS service switches off"
```

☠️ **The docs said this state should not have been there.** `docs/power/README.md`
records *"the switch does not survive a reboot … a system reboot restores the
original, expensive vector"* and calls a boot-time asserting service a
requirement. That service now exists, so after the 17:45 boot the phone came up
IMS-**off**, and the sentence in the README describes a phone that no longer
exists. Reading the state instead of the doc is what caught it — but only after
the wrong conclusion had already been written down once.

☠️ **The second half of the same mistake: a duplicate tool.** A new
`ims-settings.py` was written to reach the setter, and
[`tools/ims-toggle.py`](../../tools/ims-toggle.py) had been doing exactly that —
same QMI message, same setters — since 2026-09-02. It was deleted again. Its
own docstring already carried the answer this capture went looking for: *"On
this device calls are CSFB anyway (the IMS services have never registered)."*

### What the episode does establish

Turning voice back on is accepted by the modem and reads back `True`, and it
**does not by itself produce a registration**: 20 s and 60 s later,

```
IMS registration
  registered: 0 (NOT_REGISTERED)
  technology: 1 (WWAN)
  error code: 0
```

Error code 0 reads as "not started", not "tried and refused". And the write does
not persist: the reconcile timer fires every five minutes and had put
`voice = False` back within four. **Any VoLTE experiment on this phone has to
stop that timer first, and put it back afterwards** — otherwise the measurement
silently runs against the IMS-off vector.

☠️ `technology: 1 (WWAN)` next to `NOT_REGISTERED` is not evidence of anything;
the field only means something while registered. `ims-state.py` now prints the
enum names for exactly this reason — it used to print a bare `0`, and before
today it printed nothing at all for the registration status, because the GI
binding returns the enum directly and the tool unpacked it as a tuple.

## ☠️☠️ The Hungarian config breaks every data bearer. Reverted.

Trying to re-run the `imsd` registration on the new config found that the IMS
PDN would not come up at all:

```
couldn't connect the bearer: …MobileEquipment.Unknown:
  Call failed: internal error: invalid-profile-id
```

and ModemManager's log shows the refusal comes from the **modem**, not from MM:
`verbose call end reason (2,235): [internal] invalid-profile-id`.

It is not IMS-specific — `internet.vodafone.net` fails identically — so the
phone had **no data path at all**.

### The control

Same script, same bearer test, only the active config changed:

| config | `internet.vodafone.net` | `ims` |
|---|---|---|
| `Vodafone_Hungary_Commercial` | **fails** `invalid-profile-id` | **fails** `invalid-profile-id` |
| `ROW_Commercial` (reverted) | **connects** | **connects** |

`ROW_Commercial` (`5CF9CADA5C358517BA3BB888D0342B79BD5FADED`) is active again and
the phone has data. **The Hungarian MBN is not usable on this device as things
stand.**

☠️ **This is B→A, not A→B→A.** The return leg is missing, and two other things
changed between the legs: ModemManager was restarted, and 14 duplicate profiles
were deleted (below). Neither fixed it while the Hungarian config was active —
that is what makes the config the causal agent rather than them — but activating
a carrier config also rewrites the modem's APN profile set, so **"the config" and
"the profile table it wrote" are not separated by this measurement.**

### Two hypotheses tested and refuted on the way

- **A stale ModemManager profile cache.** Restarting ModemManager changed
  nothing; the identical error returned.
- **A full profile store.** The list had grown to 18 profiles at ids 4–22 —
  repeating `internet` / `mms` / `ims` triples, one triple per carrier-config
  activation, with the last triple **truncated at 22** and no `ims` after it,
  which looked exactly like a store that had run out. 14 duplicates were deleted
  (`--wds-delete-profile=3gpp,N`, ids 9–22, keeping `qdp_profile_ia` at 4 and one
  triple at 6–8) and **the error was unchanged with four profiles left**.
  ☠️ That deletion was a persistent write to the modem made for a hypothesis
  that then failed; the pre-deletion list is kept here as
  `profiles-before-deletion.txt`. Requesting `ip-type=ipv4v6` to match the
  existing profiles instead of creating a new one was also tried, and also
  failed.

### ☠️ An unattended script must not be able to hang

The A-B script wrapped none of its `mmcli`/`qmicli` calls in `timeout` and hung
for **40 minutes** on a `qmicli --pdc-list-configs` that never returned, then
again on the next call after that one was killed. `leg-a.sh` beside this page is
the corrected shape: every call bounded. A second bug in the same script —
an apostrophe inside `${var#...}` in a double-quoted string — made ash reject
the whole file, and because the failure was a *parse* error the script's own log
was empty and only `journalctl` had the reason. **Syntax-check a deployed script
on the device (`sh -n`) before running it unattended.**

### What this does to the VoLTE work

The point of loading the Hungarian config was to change one variable under the
`imsd` registration that failed with a `500` on 2026-09-05. That test could not
be run: the config that was supposed to be the new variable removes the data
bearer the test needs. On `ROW_Commercial` the `ims` bearer connects again — but
that is the 2026-09-05 configuration exactly, so re-running `imsd` there would
only reproduce the `500`, and it was not spent.
