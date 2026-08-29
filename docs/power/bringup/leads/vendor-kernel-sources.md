# Which vendor kernel tree is which, and how to get the one that matters

> ⚠️ **AI-generated.** Written by Claude under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement.

Established 2026-08-29, when the remaining hypothesis class became "what does the
AP *tell* the modem that we never tell it" — a question only the downstream source
answers.

## The four trees, and the one that is the oracle

☠️ **The branch name is the worst identifier here.** Read `Makefile`'s `SUBLEVEL`.

| tree | kernel | what it is |
|---|---|---|
| `FairphoneMirrors/android_kernel_fairphone_sdm632`, tag `FP3-REL-2.A.0110-20200109.202458` (= `master`) | 4.9.**112** | the 2019/2020 factory release |
| UBports GitLab, branch **`ubuntutouch`** | 4.9.**112** | ☠️ **not** the Ubuntu Touch kernel despite the name — same vintage as the factory tag |
| UBports GitLab, branch **`halium-10.0`** | 4.9.**218** | ★ **what actually runs on this phone under Ubuntu Touch** |
| on disk: `hadk22/kernel/fairphone/sdm632` (`lineage-22.2`) | 4.9.**337** | the LineageOS tree pulled in for the Sailfish port |

**The oracle's identity, confirmed on both sides.** The phone reports
`4.9.218-perf-ubuntutouch+` (read off every window in
[`../captures/2026-08-28_modem-window-both/`](../captures/2026-08-28_modem-window-both/)),
and `halium-10.0` carries `SUBLEVEL = 218` plus
`CONFIG_LOCALVERSION="-perf-ubuntutouch"` in
`arch/arm64/configs/lineageos_FP3_defconfig`. The trailing `+` is git-dirty,
added at build time.

## Where it lives now

Fetched shallowly into the existing Sailfish tree as **`ut-halium-10.0`**, with
the remote kept:

```sh
cd /mnt/1TB/Fp3-Sailfish/hadk22/kernel/fairphone/sdm632
git show ut-halium-10.0:<path>                  # read a file as the oracle has it
git diff --numstat ut-halium-10.0 HEAD -- <path>  # oracle vs the LOS tree
```

☠️ **Shallow means no common ancestor**: `git diff` and `git show` work, `git log
A..B` does not.

☠️ **Never diff the whole tree.** 4.9.112 against 4.9.337 is 11 594 files — 225
stable releases plus vendor patches, and none of it is the answer. Diff the file
you have a question about.

## Re-fetching the factory tree if it is ever needed again

It was fetched, used to answer one question, and removed — the factory 4.9.112 is
two releases behind the oracle and the file that mattered had barely moved
(`ipa_qmi_service.c`: 9 added, 3 removed between 112 and 337; `ipa_qmi_service.h`
and `smp2p_sleepstate.c` identical). One command brings it back:

```sh
git remote add fpmirror https://github.com/FairphoneMirrors/android_kernel_fairphone_sdm632
git fetch --depth=1 fpmirror \
    refs/tags/FP3-REL-2.A.0110-20200109.202458:refs/tags/fp-rel-0110
```

## What the tree is for

The candidate class that survived every elimination: the AP-side protocol the
vendor kernel speaks to the modem and mainline may not. In rough order of fit —

| area | the question |
|---|---|
| `drivers/platform/msm/ipa/ipa_v3/ipa_qmi_service.c` | ★ the `QMI_IPA_INIT_MODEM_DRIVER` handshake — the AP telling the modem its data path exists and is initialised. Fits the shape of every surviving observation: not a daemon, not a setting, done once by the kernel. On pmOS the IPA hardware probes and no channel ever comes up, and `qrtr-lookup` shows an **unattended IPA control service (49)** the modem offers |
| `drivers/soc/qcom/smp2p_sleepstate.c` | ☠️ weak: APSS is awake 100 % on both systems, so there is nothing to signal |
| `drivers/soc/qcom/qmi_*`, `net/ipc_router` | which QMI services the kernel itself subscribes to, independent of userspace |

☠️ **What no source tree can answer**: why the modem *responds* to any of this by
staying awake. That is firmware, and only DIAG sees inside.
