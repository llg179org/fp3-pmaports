# Does the audio stack cost anything at idle?

> ⚠️ **AI-generated.** Written by Claude under the direction of Lajosházi, László
> Gergely, who reviewed every change and made or reviewed every measurement.

Three boots, taken 2026-08-29 to decide whether the audio series has to wait for
the power work before it goes upstream.

**A** and **A′** are ordinary boots with the full stack. **B** is a boot with
`install <mod> /bin/false` for `snd_soc_apq8016_sbc`, `snd_soc_msm8916_digital`,
`snd_soc_wcd9335` and `slim_qcom_ngd_ctrl` — verified at **0 modules and 0 sound
cards**, which is the leg's witness.

☠️ **Read the floor (p10), not the median.** This leg cannot run inside one boot,
and the median carries the modem's per-boot duty offset — worth up to 20 mA and
visible right here as 37.5 % against 33.5 %. The floor has held at 53-56 mA across
every knob measured this week regardless of duty, so it is the one column that
survives a reboot.

☠️ **The LPASS is an output here, not a preconditon.** The plan was to require the
ADSP to be asleep in the B leg; measured, it is asleep in the A leg too — 0.0 %
awake across 184 samples with the full audio stack loaded — so that condition
separates nothing. That reading also retracts the 2026-08-28 matched pair, which
had the same master awake 100 % of a 600 s window.
