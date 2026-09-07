#!/bin/sh
# Does unbinding the himax driver release the iovcc vote the rail fix installs?
# Screen ON throughout - rebinding only works in that state.
DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh | head -1)/environ 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive false" >/dev/null 2>&1
sleep 2
l6() { grep -E '^ *l6 |2-0048-iovcc|dsi\.0-iovcc' /sys/kernel/debug/regulator/regulator_summary 2>/dev/null; }
echo "=== driver BOUND, screen ON ==="; l6
echo "$( [ -e /sys/bus/i2c/devices/2-0048/driver ] && echo '  (bound)' || echo '  (unbound)')"
echo "=== unbinding ==="
echo 2-0048 > /sys/bus/i2c/drivers/Himax-hx83112b-TS/unbind 2>/dev/null; sleep 2
echo "=== driver UNBOUND, screen still ON ==="; l6
echo "=== rebinding ==="
for t in 1 2 3; do echo 2-0048 > /sys/bus/i2c/drivers/Himax-hx83112b-TS/bind 2>/dev/null; sleep 3
  [ -e /sys/bus/i2c/devices/2-0048/driver ] && break; done
echo "  driver: $([ -e /sys/bus/i2c/devices/2-0048/driver ] && echo BOUND || echo STILL UNBOUND)"
echo "=== after rebind ==="; l6
