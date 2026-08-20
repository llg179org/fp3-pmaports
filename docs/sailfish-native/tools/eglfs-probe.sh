#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AI-generated (Claude Opus 5) under the direction of Lajosházi, László Gergely.
#
# Does Qt's eglfs platform come up on this phone's KMS device?
#
# This is the one hard prerequisite for Lipstick. The PinePhone's native Sailfish
# adaptation runs Lipstick on `qt5-plugin-platform-eglfs` over KMS/GBM with Mesa,
# configured by a two-line /etc/eglfs-config.json - and Alpine already ships the
# equivalent plugins (platforms/libqeglfs.so plus
# egldeviceintegrations/libqeglfs-kms-integration.so). What no package listing can
# say is whether they initialise on THIS display stack.
#
# ☠️ It takes the display away from phosh for about half a minute. greetd is
# stopped and started again on every exit path, and the probe ends by checking a
# session is back - a phone left with a black screen at night is not an acceptable
# way to learn something.
#
#   eglfs-probe.sh [seconds]        (default 20)

set -u

SECS=${1:-20}
OUT=/run/night/eglfs-probe.txt
QML=/run/night/probe.qml
mkdir -p /run/night
say() { echo "$*" | tee -a "$OUT"; }
: > "$OUT"

GREETD_WAS=""

restore() {
	rc=$?
	say ""
	say "# restoring the session"
	pkill -x qmlscene-qt5 2>/dev/null
	sleep 2
	if [ "$GREETD_WAS" = active ]; then
		systemctl start greetd 2>/dev/null
		sleep 12
		say "#   greetd: $(systemctl is-active greetd 2>/dev/null)"
		say "#   phoc: $(ps -eo comm | grep -cx phoc)  phosh: $(ps -eo comm | grep -cx phosh)"
		say "#   dpms: $(cat /sys/class/drm/card0/card0-DSI-1/dpms 2>/dev/null)"
	fi
	say "# restore done rc=$rc"
	exit $rc
}
trap restore EXIT INT TERM

say "# eglfs-probe uptime=$(cut -d. -f1 /proc/uptime) seconds=$SECS"

command -v qmlscene-qt5 >/dev/null 2>&1 || { say "# ABORT: qmlscene-qt5 not installed"; exit 1; }

say "== DRM devices =="
for c in /dev/dri/*; do
	say "  $c"
done
for d in /sys/class/drm/card*/device/driver; do
	say "  $(echo "$d" | cut -d/ -f5) -> $(basename "$(readlink -f "$d")")"
done
say ""

# ☠️ The card number is not a constant. The PinePhone's config names card1; on
# this phone the MSM display controller is card0 and a wrong number produces
# "Could not open DRM device", which reads like a missing driver.
CARD=$(for d in /sys/class/drm/card*/device/driver; do
	case "$(basename "$(readlink -f "$d")")" in
	msm) echo "/dev/dri/$(echo "$d" | cut -d/ -f5)"; break ;;
	esac
done)
CARD=${CARD:-/dev/dri/card0}
say "# using DRM device: $CARD"
printf '{ "device": "%s", "hwcursor": false }\n' "$CARD" > /etc/eglfs-config.json
say "# /etc/eglfs-config.json: $(cat /etc/eglfs-config.json)"
say ""

cat > "$QML" <<'QMLEOF'
import QtQuick 2.0
Rectangle {
    width: 720; height: 1440; color: "#102030"
    Text { anchors.centerIn: parent; color: "white"; font.pixelSize: 48
           text: "eglfs probe" }
    Component.onCompleted: console.log("QML_SCENE_LOADED")
}
QMLEOF

GREETD_WAS=$(systemctl is-active greetd 2>/dev/null)
say "== stopping greetd (was: $GREETD_WAS) to free the DRM device =="
systemctl stop greetd 2>/dev/null
sleep 6
say "  phoc now: $(ps -eo comm | grep -cx phoc)"
say ""

say "== running qmlscene-qt5 -platform eglfs =="
QT_QPA_PLATFORM=eglfs \
QT_QPA_EGLFS_INTEGRATION=eglfs_kms \
QT_QPA_EGLFS_KMS_CONFIG=/etc/eglfs-config.json \
QT_LOGGING_RULES="qt.qpa.*=true" \
qmlscene-qt5 "$QML" > /run/night/qmlscene.log 2>&1 &
PID=$!
sleep "$SECS"

if kill -0 "$PID" 2>/dev/null; then
	say "  ★ qmlscene is STILL RUNNING after ${SECS}s - eglfs initialised"
	ALIVE=1
else
	say "  qmlscene exited before ${SECS}s"
	ALIVE=0
fi
kill "$PID" 2>/dev/null
sleep 2

say ""
say "== qmlscene / qpa output =="
head -60 /run/night/qmlscene.log | sed 's/^/  /' >> "$OUT"
head -25 /run/night/qmlscene.log | sed 's/^/  /'
say ""
if [ "$ALIVE" = 1 ]; then
	say "# VERDICT: Qt eglfs came up on $CARD. Lipstick's platform prerequisite is met."
else
	say "# VERDICT: eglfs did not stay up - read the qpa lines above for which stage failed."
fi
