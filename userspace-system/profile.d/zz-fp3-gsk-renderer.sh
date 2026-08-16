# FP3: undo the distro's GSK_RENDERER=cairo.
#
# soc-qcom-msm8953-gpu ships /etc/profile.d/adreno-a506-quirks.sh, which sets
# the cairo renderer - and says why: "so we prepare for the removal of the
# legacy GL renderer". That is a portability decision, not a statement that GL
# is broken on this GPU, and it costs every GTK4 application its GPU: with
# cairo the whole desktop, the camera viewfinder included, is drawn on the CPU.
#
# Measured on this phone: Snapshot 130% CPU with cairo, 32% with gl. Re-checked
# 2026-08-16 on gtk4 4.22.4 / mesa 26.1.6 - the GL renderer still initialises,
# EGL gives an OpenGL ES 3.1 core context on freedreno a506.
#
# This file sorts after the quirk, so it wins. Remove it to go back.
export GSK_RENDERER=gl
