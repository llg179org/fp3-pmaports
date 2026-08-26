#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Every candidate witness for "is the panel actually off", printed side by side,
# on whichever of the two systems it is run on.
#
# ☠️ This exists because each single witness has already lied once:
#   * backlight brightness   - the oracle sat fully powered at brightness 37-38.
#   * a DBus return value    - setScreenPowerMode("off") answered true, panel lit.
#   * /sys/class/drm/*/dpms  - owned by the compositor we could not stop; a good
#                              run was declared INVALID on it.
#   * fb0/show_blank_event   - says panel_power_on = 0 while, by the 2026-08-25
#                              reading, the LCDB bias rails stay up at 5500 mV.
# So print them all, every time, and let the disagreement be visible rather than
# picking one and calling it proof. The LCDB rows are the ones the earlier UT
# floor measurement never had.
#
#   panel-witness.sh [label]
set -u
echo "=== panel-witness ${1:-} $(date -u 2>/dev/null) uptime=$(cut -d. -f1 /proc/uptime)"

echo "--- backlight"
for d in /sys/class/backlight/*/; do
	[ -d "$d" ] || continue
	printf '  %s brightness=%s bl_power=%s\n' "$(basename "$d")" \
		"$(cat "$d/brightness" 2>/dev/null)" "$(cat "$d/bl_power" 2>/dev/null)"
done
for d in /sys/class/leds/lcd-backlight; do
	[ -d "$d" ] && printf '  leds/lcd-backlight brightness=%s\n' "$(cat "$d/brightness" 2>/dev/null)"
done

echo "--- fbdev"
for f in /sys/class/graphics/fb*/blank; do
	[ -r "$f" ] && printf '  %s = %s\n' "$f" "$(cat "$f" 2>/dev/null)"
done
if [ -r /sys/class/graphics/fb0/show_blank_event ]; then
	printf '  show_blank_event: %s\n' "$(tr '\n' ' ' < /sys/class/graphics/fb0/show_blank_event)"
fi

echo "--- drm"
for f in /sys/class/drm/*/dpms /sys/class/drm/*/enabled /sys/class/drm/*/status; do
	[ -r "$f" ] && printf '  %s = %s\n' "$f" "$(cat "$f" 2>/dev/null)"
done

echo "--- regulators (LCDB / panel bias); a tree, so read the parent, not a child row"
if [ -d /sys/kernel/debug/regulator ]; then
	for d in /sys/kernel/debug/regulator/*/; do
		n=$(basename "$d")
		case "$n" in
		*lcdb*|*lab*|*ibb*|*wled*|*disp*|*panel*|*bob*)
			printf '  %s enable=%s voltage=%s\n' "$n" \
				"$(cat "$d/enable" 2>/dev/null)" "$(cat "$d/voltage" 2>/dev/null)" ;;
		esac
	done
fi
for d in /sys/class/regulator/*/; do
	n=$(cat "$d/name" 2>/dev/null) || continue
	case "$n" in
	*lcdb*|*lab*|*ibb*|*wled*|*disp*|*panel*|*bob*)
		printf '  %s state=%s microvolts=%s num_users=%s\n' "$n" \
			"$(cat "$d/state" 2>/dev/null)" "$(cat "$d/microvolts" 2>/dev/null)" \
			"$(cat "$d/num_users" 2>/dev/null)" ;;
	esac
done
grep -i -E 'lcdb|lab|ibb|wled' /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed 's/^/  sum: /'

echo "--- display clocks"
if [ -r /sys/kernel/debug/clk/clk_enabled_list ]; then
	grep -c -i -E 'mdss|dsi|byte|pclk|esc' /sys/kernel/debug/clk/clk_enabled_list 2>/dev/null \
		| sed 's/^/  enabled mdss-ish clocks: /'
	grep -i -E 'mdss|dsi|byte|pclk|esc' /sys/kernel/debug/clk/clk_enabled_list 2>/dev/null | sed 's/^/    /'
fi

echo "--- battery"
for b in /sys/class/power_supply/battery /sys/class/power_supply/pmi632-battery; do
	[ -d "$b" ] || continue
	printf '  %s current_now=%s voltage_now=%s status=%s\n' "$(basename "$b")" \
		"$(cat "$b/current_now" 2>/dev/null)" "$(cat "$b/voltage_now" 2>/dev/null)" \
		"$(cat "$b/status" 2>/dev/null)"
done
echo "=== end"
