# FP3 system-wide userspace pieces

> ⚠️ **AI-generated.** This page and the files it describes were written by
> Claude (Opus 5) working under the direction of Lajosházi, László Gergely, who
> reviewed every change and made or reviewed every measurement it rests on.

Small files that belong to the whole system rather than to one subsystem, and
that a reflash would otherwise take with it. Each one says what it undoes or
adds, and how to remove it.

## `profile.d/zz-fp3-gsk-renderer.sh` — give GTK4 its GPU back

`soc-qcom-msm8953-gpu` ships `/etc/profile.d/adreno-a506-quirks.sh`, which sets
`GSK_RENDERER=cairo` for every session on this SoC. Its own comment gives the
reason — *"so we prepare for the removal of the legacy GL renderer"* — which is
a portability decision, not a statement that GL is broken here. The cost is
that **every GTK4 application on the phone draws on the CPU**, the camera
viewfinder included, which is what a stuttering viewfinder looks like.

Measured on this device: Snapshot at **130 % CPU with cairo against 32 % with
`gl`**. Re-checked 2026-08-16 on gtk4 4.22.4 and mesa 26.1.6 — the GL renderer
still initialises, and EGL gives an OpenGL ES 3.1 core context on freedreno
a506, with no fallback and no error.

The drop-in sorts after the quirk, so it wins. Install and log in again:

```sh
scp userspace-system/profile.d/zz-fp3-gsk-renderer.sh fp3@$FP3_DEV_IP:/tmp/
ssh fp3@$FP3_DEV_IP 'sudo install -m 644 /tmp/zz-fp3-gsk-renderer.sh /etc/profile.d/'
```

☠️ **It only reaches the session at the next login.** The running phosh keeps
the environment it was started with, so nothing changes until a re-login or a
reboot. Check that it took by reading the compositor's own environment rather
than a shell's, since a shell would show the file working while the session
still ran on cairo:

```sh
tr '\0' '\n' < /proc/$(pgrep -x phosh)/environ | grep GSK_RENDERER
```

☠️ The renderer is called `gl`, not `ngl`.

Deleting the file goes back to the distro default.
