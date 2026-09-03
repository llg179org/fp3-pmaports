# The gates — what blocks work, when it expires, and whether it paid

> ⚠️ **AI-generated.** This page and the measurements on it were written by
> Claude (Opus 5) under the direction of Lajosházi, László Gergely, who reviewed
> every change.

This project defends against its own recurring mistakes with hooks: something
goes wrong once, and afterwards a gate stops it happening again. Every gate here
**can point at an incident** — and that is exactly what makes them dangerous.
The incident stays true for ever; the gate's usefulness does not.

☠️ **The question nobody had asked: has it fired JUSTLY since?** A gate that has
caught nothing in a fortnight but speaks every turn is net negative. So this page
does not record *why* a gate was born, but **what it has done since** — and when
to look again.

**The rule that frames all of it:** the net direction is fine as long as
**removing a gate is as cheap as adding one.** If a gate is harder to take out
than to put in, the set can only grow, and the rot is built in.

## The gates

| gate | event | the incident that produced it | review |
|---|---|---|---|
| `risky-target.cjs` | `PreToolUse` | 2026-08-16 boot hang. The knowledge existed in two places — `docs/deploy/README.md` and the `/fp3-kernel-test` skill — and both are **pull** mechanisms: you have to already know you need them, which is the thing that is missing at the moment they would help. This keys on the *target*, so it fires without anybody knowing it should | **2026-10-01** |
| `precompact-status.cjs` | `PreCompact` | 2026-08-23 06:10: an auto-compaction at 264k with `bandsFired: []` and zero band injections — the session's working state was lost. It does not depend on the model noticing anything; it reads the transcript already on disk | **2026-10-01** |
| `measurement-watch.cjs` | `PostToolUse`, `Stop` | "a measurement and its watcher are one object": it failed twice as prose, so it became machine-enforced. ☠️ And on 2026-09-02 the **watcher itself** was the disturbance in a leg measuring sleep length — a gate has a price. ☠️☠️ **2026-09-03: the gate was DEAD while registered** — two template strings with no `+` between them parse as a tagged-template call, `node --check` passes, and the hook threw on exactly its positive path (a launch with no watcher), so no state was written and the Stop block never fired. Found by feeding it one synthetic launch; fixed. A gate's positive path has to be *run* once, not only parsed | **2026-09-15** ☠️ *earlier date on purpose: this gate has a measured side effect* |
| `queue.cjs` | `Stop`, `SessionStart` | 2026-09-03: the hook kept its own 124-item list beside a `TODO.md` that had not changed in four days. It keeps no list now; the queue is in `TODO.md`. **2026-09-03 pm: `lane:` + the phone lease** — an upstreaming window and a phone window now draw from one queue without being handed each other's work, and a second phone task is not dispatched while the phone is leased or a measurement runs (two simulated windows + a fake measurement, all four cases behaved) | **2026-10-01** |
| `results-guard.cjs` | `Stop` | 2026-09-03: replacing the hook retired `unrecorded-result` as a side effect — the only gate here with a measured verdict — and nobody noticed until the day's `findings-log.md` entries turned out to be missing. **2026-09-03 pm:** it blocked an edit to `docs/upstreaming/STATUS.md` with instructions about power captures (measured); the dirty check is now `docs/power` + captures, and `docs/upstreaming` gets its own message | **2026-10-01** |
| ~~`autonomy.cjs`~~ | — | **retired and DELETED 2026-09-03.** Replaced by `queue.cjs` (dispatch), `results-guard.cjs` (the guards worth keeping) and `gatelog.cjs` (this page's data). It is in git history, not in the tree: a retired gate left lying about is read as a gate | — |

## The three metrics, 2026-09-03

### 1. Maintenance share — **4.4 % of commits, 5.4 % of lines**

The question: how much work goes into maintaining the tools against the real
work? Since 2026-08-20:

| | hook repo | work repo (excluding raw captures) | share |
|---|---:|---:|---:|
| commits | 32 | 697 | **4.4 %** |
| lines added | 2 616 | 45 388 | **5.4 %** |

☠️ **The captures had to come out of the denominator**, or the number flatters:
with raw data included the work repo is 131 249 lines and the share falls to
2.0 %. A denominator fattened by data dumps hides any tooling cost at all.

**Verdict: fine.** One line in twenty goes to the tools.

### 2. Per-gate precision — **not measurable retrospectively; measurable from now on**

The retired `autonomy.cjs` log recorded 37 firings:

| gate | firings | |
|---|---:|---:|
| `open-work` | 23 | 62.2 % |
| `review-due` | 9 | 24.3 % |
| `unrecorded-result` | 3 | 8.1 % |
| `OVERRIDE:human-reschedule` | 1 | 2.7 % |
| `OVERRIDE:consulted-none` | 1 | 2.7 % |

☠️ **The log recorded THAT a gate fired — never whether it was right.** So
precision cannot be computed backwards, and the rule this review was written
around — *"if the false-block rate exceeds the catches, the gate is net
negative"* — cannot be applied to any of the existing data. That is not a
detail: the missing metric is exactly the one that would justify **removing** a
gate.

What **this run** can label, because there are witnesses:

- `unrecorded-result` (3×) — named by outside review as *"the only active defence
  against compaction loss"*. No evidence of a false firing. **Justified.**
- `review-due` (9×) — the 2026-09-03 07:36 firing landed in an **idle window**
  (nothing actionable, next event eleven hours out), so its *timing* was wrong.
  The review it forced overturned three of my own numbers, so the firing was
  useful in substance. Label: **mistimed, not useless.**
- `open-work` (23×) — cannot be labelled retrospectively.

**✅ Fixed, 2026-09-03** — `plugins/fp3/hooks/gatelog.cjs`:

```
gatelog.cjs log <gate> [detail]                      # the gate calls this when it fires
gatelog.cjs outcome <id|last> catch|false|override -- "<what happened>"
gatelog.cjs report [days]                            # per gate, with a verdict
gatelog.cjs pending [gate]                           # the unlabelled firings
```

Three design choices, each against a mistake already made here:

- **One shared log, not one per gate.** Per-gate logs would be the same mistake
  as the two task lists undone that morning: a question with two answers.
- **Append-only, outcomes as separate lines.** A log rewritten to add a verdict
  loses what was believed at the time — which is the interesting part.
- ☠️ **Enforcement is not another standing instruction.** Appending "and label
  it" to every blocking message would add a line to every gate for ever, which is
  the noise that morning was spent removing. Instead **the gate's NEXT firing
  asks about the previous one**: free when gates are labelled, impossible to
  ignore for long when they are not.

`queue.cjs` and `results-guard.cjs` — the live blocking gates — are wired in. The
37 historical firings are backfilled, and the two `OVERRIDE` entries labelled
automatically.

☠️ **The remaining 31 backfilled firings are permanently unjudgeable**, and they
stay that way: retired gates (`open-work`, `review-due`), and nobody remembers
them one by one. Do not try to label them after the fact — the evidence is gone.
They are the evidence for **why** the field had to exist.

**The first real verdict, `gatelog.cjs report`, 2026-09-03:**

```
gate                     fired catch false  ovrd    ?  verdict
open-work                   23     0     0     0   23  only 0/23 labelled …
review-due                   9     0     1     0    8  only 1/9 labelled …
unrecorded-result            3     3     0     0    0  earns its place
OVERRIDE:human-reschedule    1     0     0     1    0  too few firings yet (1)
OVERRIDE:consulted-none      1     0     0     1    0  too few firings yet (1)
```

**`unrecorded-result` is the first gate in this project with a measured
verdict:** 3 firings, 3 catches, zero false.

### 3. Override rate — **5.4 %** (2/37)

Two explicit overrides: one `human-reschedule`, one `consulted none`.

**Verdict: the gates are obeyed, not routed around.** If this number goes above
20 %, it means a gate is mistuned — not that its user is undisciplined.

## ☠️ What this review found on its way

**Two gates were not under version control at all.** `fp3-risky-target.cjs` and
`precompact-status.cjs` existed only under `~/.claude/hooks/`, with zero hits in
the skills repository. A gate with no git history is **unauditable**: you cannot
ask when it was added, for which incident, or what has changed on it since —
which are precisely the three questions this page exists to answer. Both are now
in the repository and symlinked into place, and both were fire-tested after the
move.

## How to remove a gate

As cheaply as adding one — the rule at the top of this page, stated:

1. Remove the entry from `settings.json` (the file may stay, unregistered).
2. One line **here**: when it was removed, and **on what measurement**.
3. No permission is needed once the review date has passed with no catch to show.

☠️ Removing a gate is **not** an admission of failure. The gate answered an
incident; if that failure mode is gone — the tool changed, the procedure changed
— the gate lives on by its own reasoning alone, and from then on it only costs.
