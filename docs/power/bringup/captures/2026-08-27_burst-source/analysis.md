<!-- AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely. -->

# burst-source, 2026-08-27 09:40, pmOS 7.1.3 `#78-fp3` — the tracer answered "no"

360 s window, panel proven off for all 73 samples, charge input cut, 24 321 events
(`workqueue_execute_start` + `timer_expire_entry`), 71 current samples on one clock.
Raw dump: `trace.txt.gz`. Current: `current.txt`.

## The current did what the ladder said it would

    floor (p10)   57.5 mA
    median       144.2 mA
    p90          310.7 mA
    max          409.4 mA
    samples at >= 1.5x floor:  46 / 71  (65 %)

A 7x swing inside six minutes, two thirds of the samples in a burst. That is the
thing the ladders saw, reproduced in a window small enough to trace.

## ☠️ And the event rate does not move with it

Binning every event into the 5 s window that ends at each current sample, then
splitting the bins by whether that sample was a burst:

| | burst bins (n=46) | quiet bins (n=25) |
|---|---|---|
| events per 5 s bin | **313** | **316** |
| `psi_avgs_work` | 63.2 | 65.1 |
| `vmstat_update` | 17.9 | 19.4 |
| `delayed_vfree_work` | 9.2 | 10.8 |
| `lru_add_drain_per_cpu` | 4.0 | 3.9 |

Every top function is at the same per-bin rate, and the totals differ by 1 % — in
the direction *opposite* to the current. **A carpet of software wakeups that does
not change cannot be what makes the current change.** Counting work is finished as
a line of attack on the burst.

## What the carpet is, since it is worth knowing separately

Over the whole window, by workqueue function: `psi_avgs_work` 4897, `vmstat_update`
1406, `delayed_vfree_work` 800, `lru_add_drain_per_cpu` 263. By timer function:
`delayed_work_timer_fn` 6565, `process_timeout` 3434 (the sampler's own sleeps are
in here), `mix_interrupt_randomness` 2359, `tcp_orphan_update` 1527.

`psi_avgs_work` alone is over half of all workqueue executions — ~13/s, i.e. ~26
cgroups with live pressure accounting each waking every 2 s. It is **flat**
(105–151 per 10 s bin across the whole window), so it is a steady tax and not the
burst; that is consistent with the A-B-A' which priced the systemd PSI watch at
~26 mA of *median* and nothing on the floor.

## What this rules in for the next instrument

The power is going somewhere that is not a running instruction — or the CPU is
awake without generating either tracepoint (a spin, an RCU stall, an interrupt
storm handled without a workqueue), which the same trace cannot tell apart from a
rail. `burst-attrib.sh` was written for exactly this fork: it samples CPU-busy
time, cpuidle power-collapse residency, both cpufreq policies and the wlan packet
counters alongside the current, all from sysfs and with no tracepoint at all.

☠️ Do not quote any current figure from this capture as an idle number: tracing
costs time on every wakeup. What survives the overhead is the *structure*.
