#!/bin/sh
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does zeroing the sleep-set XO vote let the RPM reach vlow?
#
# One reading decides it. vlow is the RPM's XO-off record and it has been zero
# for every boot of this investigation; if it is still zero with
# clk_smd_rpm.xo_sleep_off=1 on the command line, the vote was never the
# blocker and the XO line of enquiry closes.
#
# ☠️ The parameter is checked first and the run aborts without it. A probe that
# cannot tell "the experiment did nothing" from "the experiment was not on"
# answers neither question, and the previous XO probe failed in exactly that
# way - it stopped two remoteprocs that were not holding the clock and then
# read the record as though something had changed.
#
#   vlow-probe.sh <tag> [sleep_s]
set -u
TAG=${1:?usage: vlow-probe.sh <tag> [sleep_s]}
T=${2:-60}
OUT=/run/vlow-probe.log
RTC=/sys/class/rtc/rtc0/wakealarm
PARAM=/sys/module/clk_smd_rpm/parameters/xo_sleep_off

modprobe rpm_master_stats 2>/dev/null || true

p=$(cat "$PARAM" 2>/dev/null || echo "<absent>")
printf '%s param xo_sleep_off=%s cmdline=%s\n' "$TAG" "$p" \
	"$(tr ' ' '\n' < /proc/cmdline | grep xo_sleep_off || echo none)" | tee -a "$OUT"
if [ "$p" != Y ] && [ "$p" != 1 ]; then
	echo "$TAG ABORT: experiment is not enabled, nothing to measure" | tee -a "$OUT"
	exit 1
fi

snap() {
	printf '%s %s up=%s bi_tcxo=%s apss_shut=%s apss_xo=%s vlow=%s vmin=%s susp_ok=%s susp_fail=%s\n' \
		"$TAG" "$1" \
		"$(cut -d. -f1 /proc/uptime)" \
		"$(cat /sys/kernel/debug/clk/bi_tcxo/clk_enable_count 2>/dev/null)" \
		"$(sed -n 's/^[[:space:]]*Shutdown count[[:space:]]*:[[:space:]]*//p' /sys/kernel/debug/qcom_rpm_master_stats/APSS | head -1)" \
		"$(sed -n 's/^[[:space:]]*XO shutdown count[[:space:]]*:[[:space:]]*//p' /sys/kernel/debug/qcom_rpm_master_stats/APSS | head -1)" \
		"$(sed -n 's/^Count:[[:space:]]*//p' /sys/kernel/debug/qcom_stats/vlow | head -1)" \
		"$(sed -n 's/^Count:[[:space:]]*//p' /sys/kernel/debug/qcom_stats/vmin | head -1)" \
		"$(cat /sys/power/suspend_stats/success)" \
		"$(cat /sys/power/suspend_stats/fail)" \
		| tee -a "$OUT"
}

snap baseline
for i in 1 2; do
	echo 0 > "$RTC"
	echo "+$T" > "$RTC"
	echo mem > /sys/power/state || echo "$TAG SUSPEND REFUSED cycle=$i" >> "$OUT"
	sleep 15
	snap "after-suspend-$i"
done
echo "$TAG done" >> "$OUT"
