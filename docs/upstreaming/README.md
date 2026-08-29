# Upstreaming the FP3 kernel work

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

Where each series stands, and what is blocking it. **If the vocabulary or the
shape of the process is what you need, read
[`bringup/README.md`](bringup/README.md) first** — it explains the whole thing
from the beginning, in order. The method (checklists, traps, commands) is in the
`/msm8953-mainline-pr` skill; this page is state, and it goes out of date.

## Destination

For AI-assisted work there is exactly one open door:

| destination | AI-assisted work | verdict |
|---|---|---|
| postmarketOS | banned outright | closed |
| `msm8953-mainline` | "we don't merge AI assisted work" ([issue #197](https://github.com/msm8953-mainline/linux/issues/197), 2026-07-25) | closed |
| mainline Linux (LKML) | permitted **with disclosure** | **the path** |

`msm8953-mainline` stays the base the phone runs on; that is a different job from
submission, and [`bringup/`](bringup/README.md) §7 explains why both exist.

## Timing

Send during the `-rc` phase, never into an open merge window. As of 2026-08-29:
mainline **v7.2** was released 2026-08-16, `v7.3-rc1` was not yet tagged, so the
7.3 merge window was open and closing. Check before sending:

```sh
git ls-remote --tags https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
  | sed 's|.*refs/tags/||;s|\^{}||' | sort -u -V | tail -3
```

`vX.Y-rcN` on the last line ⇒ send. A bare `vX.Y` ⇒ wait.

## The audio series

Thirteen commits on `submit/<base>/audio`, destination ASoC (`sound/for-next`)
for the driver work, the qcom/SoC tree for the board DTS.

**The argument for it** (measured 2026-08-29 against mainline `master`):
`wcd9335.c` contains no `snd_soc_jack`, `set_jack` or `mbhc` at all, and six
in-tree qcom device trees carry a WCD9335 — DragonBoard 820c, OnePlus 3/3T and
three Xiaomi msm8996/8996pro boards — none with jack detection. Plus two bugfixes
that affect every board with this codec, or every qcom board sharing an AFE port.

**Dependency status**, measured by diffing every touched file, fork base against
mainline `v7.1`:

| patches | state |
|---|---|
| the binding, the codec fixes, the DT-sourced board values, the TX gains, the q6afe fix, the OCP interrupts, the four MBHC patches — **10 of 13** | files are **byte-identical** to mainline ⇒ no fork dependency, sendable |
| the machine-driver patch (`apq8016_sbc.c`) and the board DTS — **3 of 13** | **blocked**, see below |

### The blocked chain

```
  our machine driver + board DTS
    └── MSM8953 support in apq8016_sbc.c
          └── "MSM8953/MSM8976 ASoC support" v3, patchwork series 875540,
              Adam Skladowski (code by Vladimir Lypak), 2024-07-31 — state `new`
                └── review asked it to build on Otto Pflüger's
                    "check ADSP version when setting clocks" (2023-10-29) — also stalled
```

Stephan Gerhold's objection, 2024-08-01: the patch hardcodes the Q6AFE clock-API
version per SoC, but on some SoCs it depends on the *firmware* version, so it
needs runtime detection. The author replied on 2024-08-09 that he did not fully
understand the code he was carrying and had nobody to discuss it with; nothing
since.

☠️ Our fork's variant is **further** from what the review asked for, not closer: a
plain `bool use_ibit_clk`, a `quin-iomux` window made mandatory where the posted
patch keeps it optional, and a block commented `/* HACK For making external
codecs work */` that appears in none of the posted patches. Citing the posted
series as our prerequisite would misdescribe what we are standing on.

☠️ Otto's series contains `ASoC: qcom: q6afe: remove "port already open" error`,
adjacent to our own q6afe patch — read it before sending ours.

**The constructive move** is to join that work rather than compete with it:
runtime ADSP-version detection is generic (msm8909/8916/8953/8976), we have the
hardware and the measurements both authors lacked, and it unblocks the chain from
the bottom.

## What has not been done yet

- the trial rebase onto `sound/for-next`, and the `base-commit:` it produces;
- the checker gauntlet on the rebased series;
- a functional run from the submission base on the device (needs the debug layer
  on top, and currently the phone is occupied by the power investigation);
- the decision on whether the two standalone bugfixes travel inside the series or
  separately.

## See also

- [`bringup/README.md`](bringup/README.md) — the full explanation: vocabulary,
  trees, timing, provenance rules, and the ordered runbook
- [`../TODO.md`](../TODO.md) — open items across the port
- [`../rolling-a-new-base.md`](../rolling-a-new-base.md) — moving the fork's base,
  which is a different job from upstreaming
