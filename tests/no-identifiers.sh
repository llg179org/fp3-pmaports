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
        '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b'
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
    return $rc
}

if [ "${1:-}" = "--self-test" ]; then
    # A checker that has never been shown failing has proved nothing.
    tmp=$(mktemp -d) || exit 2
    trap 'rm -rf "$tmp"' EXIT
    printf 'equipment id: <imei>\n' > "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then
        echo "SELF-TEST FAIL: a planted IMEI was not caught"; exit 2
    fi
    printf 'equipment id: <imei>\n' > "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then :; else
        echo "SELF-TEST FAIL: a redacted IMEI was reported as a leak"; exit 2
    fi
    # ☠️ A file with a stray NUL byte is "binary" to grep, which silently skips
    # it. On 2026-09-05 this check reported clean while a phone number sat in
    # such a file in the tree - the -a above is what fixes it, and this is the
    # case that proves it stays fixed.
    printf 'number: <msisdn-own>\n\0\0trailing\n' > "$tmp/planted.txt"
    if scan "$tmp" >/dev/null; then
        echo "SELF-TEST FAIL: an MSISDN hidden behind a NUL byte was not caught"; exit 2
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
