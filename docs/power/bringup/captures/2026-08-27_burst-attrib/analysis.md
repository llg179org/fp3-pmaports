<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# burst-attrib, 2026-08-27 13:11, pmOS 7.1.3 `#78-fp3` — not the CPU either

360 s, panel proven off for all 73 idle-ab samples (`waited=0s`, so every one of
the 180 attrib samples is inside the dark window), charge input cut, **no
tracepoint of any kind**. Reproduce with
`burst-attrib-fit.py captures/2026-08-27_burst-attrib/attrib.txt`.

    180 samples   floor(p10)=53   median=103   p90=222   max=473 mA
    burst (>=1.5x floor): 111    quiet: 69

| column | burst (n=111) | quiet (n=69) | ratio |
|---|---|---|---|
| `v_mV` | 4227 | 4242 | 1.00× |
| **`busy_pct`** (CPU time from `/proc/stat`) | **1.0** | **1.0** | 1.00× |
| **`pc_res_pct`** (power-collapse residency, all 8 CPUs) | **99** | **100** | 0.99× |
| `wfi_per_s` | 77 | 77 | 1.00× |
| `pc_per_s` (power-collapse entries) | 437 | 453 | 0.96× |
| `f0_kHz` / `f4_kHz` | 1 228 800 | 1 228 800 | 1.00× |
| `wlan_pps` | 2 | 2 | 1.00× |

**A 9× swing in current — 53 to 473 mA — across which the machine does not move.**
The CPUs are collapsed 99 % of the time *during the bursts*. They wake at the same
rate, run at the same frequency, do the same 1 % of work, and the wlan interface
carries the same two packets a second. Every column is flat to within measurement
noise, and the two that would prove "code is running" are flat to the digit.

## What this closes

The awake burst is **not a software wakeup and not the CPU**. That was the last
reading under which a profiler could have found it, and it is now excluded twice
over — once by the trace (`2026-08-27_burst-source/analysis.md`, event rate 313 vs
316 per 5 s) and once here, by an instrument with no tracepoints that could have
disagreed and did not.

It also re-confirms, in the middle of a burst rather than on an idle floor, the
older finding that the CPUs sit at ~99 % power-collapse residency. That was
previously read as "the CPUs are not the *floor*"; it turns out they are not the
*burst* either.

## What is left, and what it costs to spend hundreds of mA without a CPU

Three things on this phone can do that: the panel, wlan, and the modem. The panel
is proven dark and re-proven on every sample. wlan is flat at 2 pps. The modem is
untested here — and it is independently the thing that terminates every suspend on
this device (IRQ 141, the SMD edge). `burst-modem-ab.sh` runs the A-B-A' on it,
disabling the RF with `mmcli --disable` and never touching the remoteproc, because
restarting that costs audio until reboot.

If the modem also comes back flat, the remaining explanation is a rail that
nothing in `/sys` attributes, and the next instrument is a rail census timed to
the burst rather than another profiler.

☠️ Note for whoever repeats this: this capture predates the `# window_from=` mark
in `burst-attrib.sh`. It is valid only because idle-ab reported `waited=0s` — the
panel was already down when sampling began. A run with a nonzero wait and no mark
would have a lit panel, worth ~24.5 mA, averaged into its first samples.
