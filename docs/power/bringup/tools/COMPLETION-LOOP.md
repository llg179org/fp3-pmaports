# How a measurement the phone runs tells the queue it finished

☠️ **Why this exists, measured 2026-09-05.** Queue item #85 was started by
`fp3-night-start.timer`, ran 2026-09-03 23:17 → 09-04 01:15, and then sat
unclosed for **two days with nine tasks blocked behind it**. Nobody closed it
because no session was in the loop: the queue reads markers, it never infers
from the device. And it was not merely lag, it was a **deadlock** — #118, the
task that judges whether the night is good enough, carried `after: 85`, so the
evaluation that would justify closing #85 was itself blocked behind #85.

## The two halves

**On the phone**, at every exit path of the run:

```sh
fp3-measure-done <task-id> finished|aborted "<one-line summary>" [data-dir]
```

It writes `/var/log/fp3/completions/<task>.done`. ☠️ Not `/run`: #85 reboots
three times and `/run` would be erased mid-measurement.

**On the host**:

```sh
node .../hooks/queue-sync.cjs [--dry-run|--list]
```

It reads the sentinels, annotates the run's own task with what the device
reported, and releases whatever was waiting on that completion.

## The convention, and it is the whole point

```
the run task R      left alone, only annotated
its evaluator E     marked  [~]  with   until: completion:R
```

When R's sentinel appears, E flips to `[ ]` and the dispatcher hands it out.

☠️ **E must not use `after: R`.** That was the actual deadlock: a verdict cannot
gate the task that produces the verdict. `until: completion:R` depends on the run
**stopping**, which the device knows, instead of on it having **succeeded**,
which it does not.

## Three rules the design is built on, each from a failure

1. **`finished` is not `succeeded`, and the sentinel never closes a task.** The
   2026-09-03 night exited cleanly and produced nothing usable — every leg
   dropped for a median sleep of 9–18 s against a 90 s alarm. A sentinel that
   conflated exit with success would have closed the task on a failed run.
2. **Every exit path writes one, especially the abort path.** `night-run.sh` has
   three: `give_up()`, the dropped-last-leg return, and the normal end. A run
   that gives up silently is exactly the case that leaves the queue waiting for a
   night that will never report — which is why `done_sentinel` is a function.
3. **A failed queue action must not consume the sentinel.** `queue-sync` retries
   on the next run rather than marking it seen, and exits non-zero. Reporting an
   action that did not happen is the same shape as the restore that cost this
   project two dead touchscreens on 2026-09-04.

## Tested

`--list`, `--dry-run` and the real path were exercised against a scratch queue
with a sentinel for a fake task, including two controls that had to **not** move
(one waiting on a different completion, one waiting on a date). Idempotence was
checked — a second run says `nothing new` — and so was the failure path: with the
queue rejecting the ids, the sentinel stayed unconsumed and the next run retried.
