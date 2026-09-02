# userspace-power — per-device power opt-ins

> ⚠️ **AI-generated.** Written by Claude (Fable 5) under the direction of
> Lajosházi, László Gergely.

`fp3-modem-wake-arm.service` — arms the modem SMD edge as a wakeup source at
boot so an incoming call wakes the phone from s2idle. The kernel knob it flips
ships in linux-fp3 r66 and defaults to off (upstream semantics: userspace
decides). Install:

    cp fp3-modem-wake-arm.service /etc/systemd/system/
    systemctl daemon-reload && systemctl enable --now fp3-modem-wake-arm

Verified by `tests/checks/58-call-wake-test.sh` (`fp3-selftest --only call-wake`).

---

## `fp3-ims-reconcile.py` + `.service` + `.timer` — hold the IMS switches off

The modem raises an IMS PDN on APN `ims` and tears it down again 30 ms later,
every 8.4 s, forever. Every cycle needs an RRC connection, so the UE never
returns to `RRC_IDLE` — **measured three times as ~44 percentage points of modem
duty** (44.5→4.8, 45.6→asleep, 48.0→4.4), on a band-pinned A/B/A' ladder whose
repeat arm brackets the first to 0.4 pp. See
[`../docs/power/bringup/captures/2026-09-02_ims-ladder/`](../docs/power/bringup/captures/2026-09-02_ims-ladder/).

Switching every IMS service off stops it dead, and on this network costs
nothing measurable: the phone **rings** (503 ms device-side), **answers**,
carries **audio both ways** for a minute, and **receives SMS** (~5 s) over the CS
path — [`../docs/power/bringup/captures/2026-09-02_reachability-ims-off/`](../docs/power/bringup/captures/2026-09-02_reachability-ims-off/).

☠️ **This is a reconciler, not a setting.** The write does **not** survive a
reboot: measured 2026-09-02, after a reboot and before any write, the original
vector was back. Without something re-asserting it, every restart silently
returns the phone to ~48 % modem duty and nobody notices.

☠️ **Ordering does not fix that**, which is why the unit does not try:
`After=ModemManager.service` only means the daemon started, while "the daemon
finished initialising the modem" is a different moment. The script reads,
compares, writes **per switch**, reads back, and retries with backoff; the timer
runs it again every five minutes.

☠️ **IMS off means no VoLTE and no IMS-routed SMS.** On this device the IMS
services have never registered and calls are CSFB, so today that costs nothing —
but the CS fallback is what carrier 2G/3G shutdowns eventually remove. When that
happens this lever stops being free, and the answer becomes an AP-side IMS
client rather than a switch. See
[`../docs/power/bringup/leads/ims-missing-ap-half.md`](../docs/power/bringup/leads/ims-missing-ap-half.md).

Install:

    cp fp3-ims-reconcile.py /usr/local/bin/ && chmod +x /usr/local/bin/fp3-ims-reconcile.py
    cp fp3-ims-reconcile.service fp3-ims-reconcile.timer /etc/systemd/system/
    systemctl daemon-reload && systemctl enable --now fp3-ims-reconcile.timer

Read the history it leaves behind — every drift is timestamped:

    journalctl -u fp3-ims-reconcile --no-pager | grep -i drift

## `fp3-login-ledger.sh` — the device-side half of the measurement lock

Every ssh login into the phone writes one tab-separated line into
`/var/log/fp3/logins.tsv`: wall clock, monotonic seconds, client address, whether
a measurement lock was held, pid, and the command. While `/run/fp3-measuring`
exists it also shouts on **stderr** that a measurement is running and that this
login just woke the phone.

☠️ **It is advisory and must stay advisory.** A phone that has to remain
recoverable cannot have a lock that refuses logins — a spoiled measurement costs a
night, a stranded device costs a day and a physical button press. Everything in
the script is wrapped so a failure inside it cannot fail the login.

**Why a ledger and not a counter.** The measurement legs already grep the journal
for `Accepted publickey` and mark a leg disturbed on `logins > 0`. That number has
no owner, so it can only convict: on 2026-09-02 a host-side watchdog polling every
300 s would have made every leg of an overnight run read as disturbed, on data
only the watcher had spoiled. With the ledger the morning can attribute — this
login was the watchdog at 19:52, that one was a person at 03:14 — and mark the leg
on the second, not the first.

Install:

```sh
install -m755 fp3-login-ledger.sh /usr/local/bin/
mkdir -p /root/.ssh && echo '/usr/local/bin/fp3-login-ledger.sh' >> /root/.ssh/rc
```

☠️ `/run` is tmpfs, so a measurement that reboots must re-assert the lock on every
boot; `night-run.sh` writes it at every step for exactly that reason.
