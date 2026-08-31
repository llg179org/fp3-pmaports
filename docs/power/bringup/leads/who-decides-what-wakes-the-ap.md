# Who decides what wakes the AP — ModemManager, or the kernel?

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed every claim it rests on.

Source analysis, 2026-08-31. Upstream ModemManager `5e91dd2` (1.25.95); vendor
msm-4.9 tree on disk at `hadk22/kernel/fairphone/sdm632/`; mainline as running
on this device (`debug-int/7.1.3`).

**The question it answers:** *"when no call is in progress, put the modem into a
mode it can still be woken from by an incoming call"* — where does that belong,
and what is actually missing?

## 1. The mode already exists, and this distribution already enables it

ModemManager's `--test-quick-suspend-resume` wires `MM_BASE_MANAGER_CLEANUP_TERSE`
to logind's sleep signal (`src/main.c:96`), whose own message reads *"only send
important signals (call/text)"*. It walks `mm_iface_modem_3gpp_terse`, which on a
QMI modem unregisters NAS `serving_system_events`, NAS `system_info`, NAS
`network_reject_information`, and — when DSD is supported — the DSD
`System Status Change` indication.

pmOS ships it: `/usr/lib/systemd/system/ModemManager.service.d/quick-suspend-resume.conf`,
owned by `postmarketos-base-ui-modemmanager-systemd`.

So the requested feature is **not missing from upstream**. Details and the
measurement history are in [`modemmanager-suspend-modes.md`](modemmanager-suspend-modes.md);
the measured facts that matter here:

- **the call survives terse** — terse applied at 07:17:04, asleep 07:17:04→07:17:19
  by the kernel's own marks, `call state changed: unknown -> ringing-in` at
  07:17:19. One second wide, so no averaging can hide it;
- **and terse does not silence the modem.** Four `terse state 3GPP … done` lines
  per round, and NAS (port 40) and DSD (port 52) indications still arriving
  *inside* the sleep window (`captures/2026-08-30_wake-qmi-sms/`).

## 2. Why the failure is invisible — and the upstream patch for it

`ri_serving_system_or_system_info_ready` and `ri_system_status_ready`
(`src/mm-broadband-modem-qmi.c`) guard their error message with
`if (ctx->enable)`. On the **disable** path a refusal therefore prints nothing,
not even at debug level, and the handler then does
`/* Just ignore errors for now */` and returns success.

⇒ *"terse … done"* in the journal means **the step ran**, never that the modem
obeyed. A witness built so it cannot say no.

Patched upstream-bound, branch `qmi-report-failed-unregister` in the
ModemManager checkout: keep the register direction exactly as it was — a failure
there is benign and the code deliberately assumes the indication is already on —
and `mm_obj_warn` on the unregister direction. Control flow is unchanged; the
task still returns success, so no state transition behaves differently. It only
makes the refusal visible, which is the prerequisite for every question after it.

☠️ Noted while reading, deliberately **not** in that patch:
`self->priv->unsolicited_registration_events_enabled` is written at two sites and
**read nowhere** in the file. It is dead state, so correcting it would buy
nothing and would dilute a one-thing patch.

## 3. What the downstream actually does — and it is not in a daemon

There is no ModemManager on the vendor stack. The equivalent decision lives in
the kernel's IPC router, and it is a **filter on the wakeup source, by QMI
service id** (`net/ipc_router/ipc_router_core.c:4347`):

```c
if (!is_sensor_port(rport_ptr)) {
        if (!xprt_info->dynamic_ws) {
                __pm_stay_awake(&xprt_info->ws);
                pkt->ws_need = true;
        } else {
                if (is_wakeup_source_allowed) {
                        __pm_stay_awake(&xprt_info->ws);
                        pkt->ws_need = true;
                }
        }
}
```

Three separate mechanisms, all absent from mainline:

| downstream | what it does |
|---|---|
| `is_sensor_port()` (`:236`) | service id 400 and 256–320 **never** take a wakeup source (277 and 287 excepted — proximity and pick-up gesture *are* allowed to wake) |
| `qcom,dynamic-wakeup-source` (`ipc_router_glink_xprt.c:877`) | per-transport DT property; on such a transport a wakeup source is taken **only while the flag below is set** |
| `msm_ipc_router_set_ws_allowed()` driven by `smp2p_sleepstate.c` | the PM notifier sets it **true on `PM_SUSPEND_PREPARE`** and **false on `PM_POST_SUSPEND`** — so those transports take wakeup sources only across a suspend, and none at all while the AP is awake |

☠️ The direction is the opposite of the obvious guess, and worth stating so
nobody re-derives it backwards: `ws_allowed` is **enabled** when going to sleep.
It is not a mute switch; it is "while awake there is no point taking wakelocks,
while asleep an arriving packet must be able to wake us".

☠️ And the same notifier's *other* half — clearing SMP2P bit 12 (`PROC_AWAKE_ID`)
to tell the remote the AP is going down — targets **`qcom,remote-pid = <2>`**,
the ADSP, in every vendor DT that carries it (`msm8937-smp2p.dtsi:164`,
`sdm670-smp2p.dtsi:137`). The modem is pid 1. **Downstream never tells the modem
the AP is asleep either.**

## 4. The mainline gap, which is the load-bearing one

```sh
grep -rn 'pm_stay_awake\|pm_wakeup\|wakeup_source\|device_init_wakeup' net/qrtr/ drivers/rpmsg/
```

returns **nothing** on the tree this device runs. Mainline QRTR has no
wakeup-source handling at all: no per-service filter, no per-transport property,
no suspend-scoped gate. Every packet's effect on the AP's sleep is whatever the
underlying `smd`/`glink` edge does, uniformly, for every service.

⇒ **ModemManager cannot deliver the requested behaviour on this platform, and
neither could a perfect ModemManager.** It can ask the modem to stop sending; it
has no say in what wakes the application processor. The measurement already shows
both halves of that: the asking demonstrably fails, and the traffic that arrives
ends the suspend regardless of what the daemon believes.

The list of what wakes us is already measured
([`project_fp3_modem_wake`](selective-smd-wakeup.md), 2026-08-30): a call is QRTR
**port 39** (Voice); the noise is **40** (NAS) and **52** (DSD); with the radio
off the phone slept 1802 s, so the noise comes from the network rather than from
our own stack.

## 5. What follows, in the order the evidence supports it

1. **The MM patch above** — it costs nothing and turns "terse done" from an
   assertion into a report. Until it lands, every further terse question is
   unfalsifiable.
2. **Then ask why the unregister is refused**, with the warning now visible. Two
   candidates the journal could not previously separate: the modem refuses, or
   what still arrives are messages terse never asked about.
3. ☠️ **Do not reach for `--test-low-power-suspend-resume`.** A radio in low power
   does not deliver a call, and the target is parity *at the oracle's
   responsiveness*. Measured on 2026-08-30: the low-power arm loses the call.
4. **The kernel-side filter is the real lever, and it is a mainline gap, not a
   port.** A downstream copy would not be accepted — the service-id table is a
   vendor policy hardcoded in a router. What is defensible upstream is the
   general shape: let a QRTR service declare whether its traffic may wake the
   host. That is a design discussion on `linux-arm-msm`, not a patch to write
   this week, and it is the same conversation as
   [`selective-smd-wakeup.md`](selective-smd-wakeup.md).

## ☠️ What this page does not claim

It does not claim ModemManager causes the modem's duty. With the daemon
**stopped**, the modem is 5.0 % awake across a real 602 s suspend
(`captures/2026-08-31_mpss-across-suspend-nomm/`) — the same as an awake window.
The one across-suspend figure with the daemon running is 45 % and is **n=1**
(2026-08-30), unreconciled against a flat awake-window A-B-A′ (4.9 % running vs
5.1 % stopped). What *is* measured against the daemon is narrower and enough to
justify everything above: with it running, every suspend dies within 16–53 s on
the modem's SMD edge, five times out of five.
