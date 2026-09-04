#!/bin/sh
# #142 - what the touch i2c pads (gpio10/11) look like at the moment of the stall.
set -u
bus=$(for a in /sys/bus/i2c/devices/i2c-*; do
        case "$(readlink -f "$a")" in *78b7000*) basename "$a" | cut -d- -f2 ;; esac; done)
ts=2-0048; drv=Himax-hx83112b-TS
DB=$(tr '\0' '\n' < /proc/$(pgrep -x phosh|head -1)/environ | grep DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
ss(){ su fp3 -c "DBUS_SESSION_BUS_ADDRESS='$DB' gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive $1" >/dev/null 2>&1; }

dump() {
  echo "     runtime_status = $(cat /sys/devices/platform/soc@0/78b7000.i2c/power/runtime_status)"
  for p in /sys/kernel/debug/pinctrl/1000000.pinctrl; do
     [ -r "$p/pinmux-pins" ] && grep -E '^pin (10|11) ' "$p/pinmux-pins" | sed 's/^/     mux: /'
     # pin 64 = touchscreen reset (reset-gpios = <&tlmm 64 GPIO_ACTIVE_LOW>)
     # pin 65 = touchscreen interrupt; pin 61 = panel reset
     [ -r "$p/pinmux-pins" ] && grep -E '^pin (61|64|65) ' "$p/pinmux-pins" | sed 's/^/     mux: /'
     [ -r "$p/pinconf-pins" ] && grep -E '^pin (10|11|61|64|65) ' "$p/pinconf-pins" | sed 's/^/     cfg: /'
  done
  grep -E 'gpio-(10|11|61|64|65)\b' /sys/kernel/debug/gpio 2>/dev/null | sed 's/^/     gpio: /'
}

for arm in OFF ON; do
  [ "$arm" = OFF ] && ss true || ss false
  sleep 3
  echo "=== arm $arm: dpms=$(cat /sys/class/drm/card0/card0-DSI-1/dpms)"
  echo "  -- before unbind:"; dump
  echo "$ts" > "/sys/bus/i2c/drivers/$drv/unbind" 2>/dev/null; sleep 3
  echo "  -- after unbind, just before the probe:"; dump
  r=$(python3 -c "
import fcntl,os,time
f=os.open('/dev/i2c-$bus',os.O_RDWR)
try:
    fcntl.ioctl(f,0x0706,0x50); t=time.monotonic()
    try: os.read(f,1); e=0
    except OSError as ex: e=ex.errno
    print('%.4f errno %d'%(time.monotonic()-t,e))
finally: os.close(f)")
  echo "  -- PROBE: $r"
  echo "  -- after the probe:"; dump
  ss false; sleep 2
  for t in 1 2 3; do echo "$ts" > "/sys/bus/i2c/drivers/$drv/bind" 2>/dev/null; sleep 4
      [ -e "/sys/bus/i2c/devices/$ts/driver" ] && break; done
  echo "  -- rebound: $(basename "$(readlink /sys/bus/i2c/devices/$ts/driver 2>/dev/null)" 2>/dev/null || echo FAILED)"
  echo
done
