#!/bin/sh
# no-identifiers.sh - refuse to publish subscriber or premises identifiers.
#
# This is a REPOSITORY check, not a device check, so it does not live in
# checks/ and fp3-selftest does not run it: captures are pasted in from the
# phone, and ofono/dmesg output carries IMEI, IMSI, ICCID, the caller's number
# and the home access point's BSSID as a matter of course. Every one of those
# has reached a pushed commit at least once (2026-09-05).
#
#   sh tests/no-identifiers.sh            # scan the working tree
#   sh tests/no-identifiers.sh --self-test # prove it still catches a planted one
#
# Exit 0 clean, 1 if anything matched. Run it before committing a capture.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Patterns are deliberately narrow: broad ones match device-tree hex and battery
# tables, and a check that cries wolf gets ignored, which is the same as absent.
#
# ☠️ The last pattern is not an identifier at all - it is the DEVICE PASSWORD.
# fp3-ssh gets root by `echo <pw> | sudo -S ...`, so the password sits in the
# command line of every privileged process, and any capture that includes a
# process listing (`ps -o args`, `ps aux`, a `pgrep -a`) carries it in clear.
# Found 2026-09-05 while hunting a stray script with `ps -o pid,args`. The
# password is never written into this file, so the pattern matches the SHAPE:
# a quoted echo piped into `sudo -S`, with a LITERAL inside the quotes -
# `echo '$pw' | sudo -S` in a script is the correct way to write it, and so is
# the single-quote idiom `echo '"$FP3_PW"' | sudo -S` used to expand a
# variable inside an otherwise single-quoted remote command. So the pattern
# requires the quoted text to contain NO `$` at all: a literal secret has
# none, and every correct form has one.
scan() {
    dir=$1
    rc=0
    # IMEI: 15 digits, and 35 is the TAC range these phones report
    # IMSI: MCC 216 (HU) + 12 digits          ICCID: 89 + 17-18 digits
    # MSISDN: +36 / 0036 followed by 9 digits, spaces tolerated
    # BSSID/MAC: only lowercase colon form; the uppercase one is a PDC config ID
    for pat in \
        '\b35[0-9]{13}\b' \
        '\b216[0-9]{12}\b' \
        '\b89[0-9]{17,18}\b' \
        '(^|[^0-9])(\+|00)[[:space:]]?36([[:space:]]?[0-9]){9}([^0-9]|$)' \
        '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b' \
        "echo[[:space:]]+'[^'\$]*'[[:space:]]*\\|[[:space:]]*sudo[[:space:]]+-S"
    do
        hits=$(grep -raEn "$pat" "$dir" \
                 --exclude-dir=.git \
                 --exclude-dir=device_tree \
                 --exclude='*.dtsi' --exclude='*.dts' \
                 --exclude="$(basename "$0")" 2>/dev/null \
               | grep -vE '<(imei|imsi|iccid|msisdn|caller|home-ap-bssid|fp3-wlan-mac)[^>]*>' \
               | grep -vE '([0-9A-Fa-f]{2}:){6}')
        if [ -n "$hits" ]; then
            echo "$hits" | cut -c1-160
            rc=1
        fi
    done

    # ☠️ The device password itself, when the environment knows it. This file
    # must never contain the secret, so the check is only possible when the
    # caller has sourced fp3-env.sh - and it is silently skipped otherwise,
    # which is exactly how this leak survived: 14 sites across 13 files, in a
    # PUBLIC repository and in 1317 commits of history, found 2026-09-05 only
    # because somebody grepped for it by hand. Matching lines are printed with
    # the secret masked, so running the checker never reprints it.
    if [ -n "${FP3_PW:-}" ]; then
        hits=$(grep -raFn "$FP3_PW" "$dir" \
                 --exclude-dir=.git \
                 --exclude="$(basename "$0")" 2>/dev/null)
        if [ -n "$hits" ]; then
            echo "$hits" | sed "s/$FP3_PW/<DEVICE-PASSWORD>/g" | cut -c1-160
            rc=1
        fi
    fi
    return $rc
}

if [ "${1:-}" = "--self-test" ]; then
    # A checker that has never been shown failing has proved nothing.
    tmp=$(mktemp -d) || exit 2
    trap 'rm -rf "$tmp"' EXIT
    # ☠️ THE PLANTED VALUE MUST LOOK REAL, OR NOTHING IS PROVED. Until
    # 2026-09-05 the first case below planted the *redaction marker* `<imei>`
    # and expected it to be caught, which cannot happen - so --self-test failed
    # on its first assertion every time it was run, and the guard's own proof
    # that it still works had never once passed. The scan itself was fine; the
    # thing that was supposed to vouch for it was not. A safety net whose test
    # is broken is a safety net nobody has checked.
    #
    # The values here are SYNTHETIC and assembled from parts so this file never
    # contains a plausible identifier of its own: 35 + zeros is IMEI-shaped and
    # belongs to no device.
    fake_imei="35$(printf '0%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)6"
    printf 'equipment id: %s\n' "$fake_imei" > "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then
        echo "SELF-TEST FAIL: a planted IMEI-shaped number was not caught"; exit 2
    fi
    printf 'equipment id: <imei>\n' > "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then :; else
        echo "SELF-TEST FAIL: a redacted IMEI was reported as a leak"; exit 2
    fi
    # ☠️ A file with a stray NUL byte is "binary" to grep, which silently skips
    # it. On 2026-09-05 this check reported clean while a phone number sat in
    # such a file in the tree - the -a above is what fixes it, and this is the
    # case that proves it stays fixed.
    fake_msisdn="+36$(printf '0%.0s' 1 2 3 4 5 6 7 8 9)"
    printf 'number: %s\n\0\0trailing\n' "$fake_msisdn" > "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then
        echo "SELF-TEST FAIL: an MSISDN-shaped number hidden behind a NUL byte was not caught"; exit 2
    fi

    # The literal device password, when the environment knows it. Uses a
    # sentinel rather than the real secret, so the test proves the mechanism
    # without the file or the test output ever carrying it.
    ( FP3_PW=SENTINEL-PASSWORD-FOR-SELFTEST
      printf 'ssh host "echo %s | sudo -S id"\n' "$FP3_PW" > "$tmp/planted.txt"
      export FP3_PW
      if scan "$tmp" >/dev/null; then
          echo "SELF-TEST FAIL: a planted device password was not caught"; exit 2
      fi ) || exit 2

    # A pasted process listing carrying the device password, shape only.
    printf "%s\n" "1234 sudo -S sh -c ..." > "$tmp/planted.txt"
    printf "%s\n" "1234 ash -c echo 'REDACTED-SHAPE' | sudo -S sh -c ls" >> "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then
        echo "SELF-TEST FAIL: a pasted process listing leaking the sudo password was not caught"; exit 2
    fi

    # Known negatives: a modem PDC config ID (20 colon-separated hex bytes, so
    # its first six look exactly like a MAC) and a power log whose columns run
    # together into something the MSISDN pattern used to match.
    printf 'ID:          36:26:71:77:12:83:A0:3E:7E:9F:9B:ED:61:76:DD:B0:11:22:33:44\n' > "$tmp/planted.txt"
    printf '8 2100 3692 0 96 4254570 270 awake 2 0\n' >> "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then :; else
        echo "SELF-TEST FAIL: a PDC config ID or a power log was reported as a leak"; exit 2
    fi
    echo "SELF-TEST OK: catches a planted IMEI and one behind a NUL byte,"
    echo "              accepts the redacted form, and does not fire on a"
    echo "              PDC config ID or a power log"
    exit 0
fi

if scan "$ROOT"; then
    echo "no-identifiers: clean"
    exit 0
else
    echo
    echo "no-identifiers: FOUND the above. Redact before committing."
    echo "  cmd: sh tests/no-identifiers.sh"
    exit 1
fi
