# #130 — the AFE service api_version this ADSP reports

**Measured 2026-09-05 on `debug-int/7.1.3`: `api_version = 2`,
`api_branch_version = 0`, query returned success.**

```
r:q6ver q6core_get_svc_api_info ret=$retval:s32 svcid=$arg1:u32 \
        f_svc=+0($arg2):u32 f_api=+4($arg2):u32 f_branch=+8($arg2):u32

q6ver: (q6afe_probe+0x3c/0xa0 [q6afe] <- q6core_get_svc_api_info)
       ret=0  svcid=4  f_svc=0  f_api=2  f_branch=0
```

This is the number `docs/upstreaming/README.md` names as *"the one number the
whole redesign turns on"* — the AFE service's API version, which the generic
q6afe clock-set change must dispatch on. It is a device reading, not an argument.

## Why the numbers are trustworthy, and how the first attempt was wrong

Two checks are built into the line above, and both had to pass:

* **`ret=0`.** `q6core_get_svc_api_info()` returns 0 only when it found the
  service in the ADSP's list and wrote the fields. A zero in `f_api` with a
  non-zero `ret` would have meant "not found", which reads identically.
* **`f_svc=0`.** The function never writes `ainfo->service_id` — only
  `api_version` and `api_branch_version`. So a zero there is the expected value,
  and it confirms the pointer is aimed at the struct the function filled rather
  than at something that merely looks plausible.

☠️ **The first read was one field out and would have been reported as
`api_version = 0`.** It fetched `+0` and `+4` as api and branch, but
`struct q6core_svc_api_info` (`sound/soc/qcom/qdsp6/q6core.h:6`) is
`service_id, api_version, api_branch_version` — so `+0` was the service_id the
function never writes, and the "branch=2" was the api_version. Caught by reading
the header rather than by the number looking wrong: **0 and 2 are both perfectly
plausible values**, which is exactly why a hand-computed offset needs a field
whose value is known in advance before any of it is quoted.

## Method: no rebuild, no flash

Nothing in the tree prints this. `q6afe_probe()` calls
`q6core_get_svc_api_info(adev->svc_id, &afe->ainfo)` and the value is never
logged, never exposed in sysfs or debugfs, and `afe->ainfo` occurs exactly twice
in `q6afe.c` — its declaration and that call.

Route taken: a **kretprobe with entry-argument access at return**
(`$arg1`/`$arg2` are available at return on this arm64 kernel), triggered by an
APR-bus unbind and rebind of the AFE service so `q6afe_probe()` runs again:

```
/sys/bus/aprbus/drivers/qcom-q6afe/{unbind,bind}   <<  aprsvc:service:4:4
```

Rejected on the way, and why: `/proc/kcore` does not exist on this kernel, so the
static `g_core` (present in kallsyms at the time of the read) cannot be walked
from userspace; and reading it through an `@g_core` kprobe would need
hand-computed offsets through `struct q6core`, which contains a
`wait_queue_head_t` and a `struct mutex` whose sizes depend on config — the same
class of error that the `+0`/`+4` slip above shows is not self-announcing.

## ☠️ The method has a cost: it breaks audio

The unbind/rebind leaves the AFE ports wedged. Immediately after:

```
q6afe-dai …: fail to start AFE port 7f
ASoC error (-110) at snd_soc_dai_prepare() on QUIN_MI2S_RX
qcom-q6afe aprsvc:service:4:4: AFE enable for port 0x1016 failed -110
```

A second unbind/rebind did **not** clear it (30 error lines after). It took a
reboot, after which the card came back with 0 errors and a PCM verified
`state: RUNNING` on a silent `aplay`.

**So do not run this on a phone that is mid-measurement or needed for a call
test.** It cost a reboot here, at a moment when the reachability census wanted an
undisturbed night. If the number is ever needed again, the cheap way is a
one-line `dev_info` in `q6afe_probe()` folded into whatever flash happens next -
it prints at boot and costs nothing.

## What this does NOT decide

The threshold is not ours to state. Our tree stores `ainfo` and branches on it
nowhere; the dispatch by firmware version is patch 3/4 of Otto Pflüger's *ASoC:
qcom: check ADSP version when setting clocks* v2, which is not in mainline. What
this measurement provides is the **input** to that condition on this device, not
the condition. Which branch `api_version = 2` selects has to be read off that
patch, and this page deliberately does not guess it.
