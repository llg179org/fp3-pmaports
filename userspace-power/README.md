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
