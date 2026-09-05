# Upstreaming the FP3 kernel work

> ⚠️ **AI-generated.** This page — and the code, device tree and tooling it
> describes — was written by Claude (Opus 5) working under the direction of
> Lajosházi, László Gergely, who reviewed every change and made or reviewed
> every measurement it rests on. Kernel commits carry `Co-authored-by: Claude`;
> anything prepared for the LKML carries `Assisted-by:` instead and never a
> `Signed-off-by` from the assistant, since only a human can certify the DCO.

Where each series stands, and what is blocking it. **The per-series state, review rounds, test evidence and dependency list now live on [`STATUS.md`](STATUS.md)**; this page keeps the analysis. **If the vocabulary or the
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
curl -s https://www.kernel.org/releases.json |
  python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["releases"] if x["moniker"]=="mainline"][0]; print(r["version"], r["released"]["isodate"])'
```

A version containing `-rc` means the rc phase is running and you may send. A
bare `vX.Y` means that release has just been tagged and the **merge window is
open** — wait.

☠️ **Do not answer this from the tag list.** `git ls-remote --tags … | sort -V |
tail` looks like the obvious check and is wrong in a way that always reads
"safe to send": version sort places `v7.2` *before* `v7.2-rc1`, so the last line
is an `-rc` tag whether the release is out or not. Measured 2026-08-30 — the
heuristic was in this page for a day before it was tried against a known state.

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

### ★ The chain is shorter than it looks — read 2026-08-30 in mainline

Otto's series was **not** rejected, and most of its foundation has since landed.
What is in mainline `master` today:

| piece | where |
|---|---|
| a per-service firmware API version query, handling **both** shapes of the ADSP's service list — which was Srinivas's own objection to Otto's 1/4 | `q6core_get_svc_api_info()`, `EXPORT_SYMBOL_GPL`, `q6core.h` |
| q6afe **already asks for it at probe** and keeps it | `q6afe.c`, `q6core_get_svc_api_info(adev->svc_id, &afe->ainfo)` |
| a param path that takes a NULL port — Srinivas's own 2023-12-11 cleanup sketch | `q6afe_set_param(afe, NULL, …)` in `q6afe_set_lpass_clock()` |

What is **not** there is only the last step: `q6afe_port_set_sysclk()` still
dispatches **by clock id alone** — `LPAIF_BIT_CLK` and `LPAIF_OSR_CLK` always take
the old `AFE_PARAM_ID_LPAIF_CLK_CONFIG` path, `LPAIF_DIG_CLK` the old digital-codec
path, and only an explicit `Q6AFE_LPASS_CLK_ID_*` takes the new
`AFE_PARAM_ID_CLOCK_SET` path. The firmware version sits in `afe->ainfo`, unread
by that switch.

So the missing work is one self-contained change in `q6afe.c`: **when the firmware
is the newer kind, serve `LPAIF_BIT_CLK` from the new clock-set API** instead of
the old one. That is exactly what Stephan asked Adam for in 2024, what Otto's 3/4
attempted before the foundation existed, and what Srinivas sketched the plumbing
for in 2023.

And it changes what our own series needs: a machine driver on MSM8953 could then
keep asking for `LPAIF_BIT_CLK`, as `apq8016_sbc` already does for msm8916, and get
the right thing — **no per-SoC hardcode, no `bool use_ibit_clk`, no
`enum afe_clk_api`**. Most of the blocking patch stops being necessary; what
remains from Adam's series is the Quinary MI2S support and the compatible plus its
binding, neither of which drew an objection.

**Re-checked on the destination tree, 2026-08-30.** The reading above was taken
on `torvalds/master`, which is the wrong tree to conclude from — `q6afe` is
actively developed (Richard Acayan's "internal mi2s support" was accepted
2026-07-30, Val Packett's clk-vote fix went through in May), so the claim had to
be re-tested against `sound/for-next` before any mail could rest on it. Result:
`q6afe.c` is **byte-identical** on the two trees (same md5, 61 750 B), so on
`for-next` too `q6afe_port_set_sysclk()` still dispatches by clock id alone and
`afe->ainfo` occurs exactly twice in the file — its declaration and the probe
that fills it. Nothing reads it. The finding holds where it matters.
(`for-7.4` does not exist yet — 404 — which is what an open merge window looks
like on the maintainer's side.)

☠️ **Measured 2026-09-05: this ADSP reports AFE `api_version = 2`,
`api_branch_version = 0`**, with the query returning success (so the zero in the
branch field is a real zero, not a lookup miss). Read with a kretprobe on
`q6core_get_svc_api_info()` triggered by an APR-bus rebind of the AFE service —
no rebuild and no flash, because nothing in the tree prints it. Full method,
both self-checks, and ☠️ the cost (the rebind wedges the AFE ports and needed a
reboot) in
[`../audio/bringup/captures/2026-09-05_130-afe-api-version/`](../audio/bringup/captures/2026-09-05_130-afe-api-version/README.md).

What that number *selects* is still not ours to say: our tree branches on
`ainfo` nowhere, and the dispatch by firmware version is patch 3/4 of Otto's v2,
which is not in mainline. The measurement supplies the condition's **input** on
this device, not the condition.

**The constructive move** is to join that work rather than compete with it: the
change is generic (msm8909/8916/8917/8953/8976), it is small now that its
foundation is upstream, and we have the hardware and the measurements both authors
lacked. Announce it on Otto's thread and Adam's rather than posting a third
competing series.

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
