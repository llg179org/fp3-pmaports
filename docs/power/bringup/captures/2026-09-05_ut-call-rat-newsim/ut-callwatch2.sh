#!/bin/sh
# UT call RAT sampler, run #2 (2026-09-05).  One variable vs run #1: the SIM card.
#
# Columns, and why each exists:
#   tech    NetworkRegistration.Technology     - what the call actually runs on
#   reg     NetworkRegistration.Status
#   imsreg  IpMultimediaSystem.Registered      - the REAL IMS state.  Run #1 did
#           (VoiceCapable is NOT sampled - see the header note)  not have this column; it counted
#   imsdev  imsradio* netdevs                    netdevs instead, which is what the
#           (kept only so the column named "ims" in run #1 stays comparable)
#   states  VoiceCallManager call states
DUR=${DUR:-420}
OUT=${OUT:-/home/phablet/ut-callwatch2.txt}
M=/ril_0
prop() {   # $1 = interface, $2 = property; prints the bare value
    dbus-send --system --print-reply --dest=org.ofono "$M" "org.ofono.$1.GetProperties" 2>/dev/null \
      | grep -A2 "string \"$2\"" \
      | grep -oE 'string "[^"]*"|boolean (true|false)|byte [0-9]+' \
      | sed -n '2p' | sed -e 's/^string "//' -e 's/"$//' -e 's/^boolean //' -e 's/^byte //'
}
callstates() {
    dbus-send --system --print-reply --dest=org.ofono "$M" org.ofono.VoiceCallManager.GetCalls 2>/dev/null \
      | grep -oE '"(active|held|dialing|alerting|incoming|waiting|disconnected)"' | tr -d '"' | tr '\n' ','
}
imsdev() { ls /sys/class/net 2>/dev/null | grep -c imsradio; }

{
  echo "== ut-callwatch2 start $(date '+%F %T')  (${DUR}s)"
  # ☠️ Never print the ICCID or IMSI: a capture is committed to a public repo.
  # The last 4 digits distinguish the cards in play without identifying anyone,
  # which is the only thing a reader of this file actually needs.
  echo "== card:    iccid=...$(prop SimManager CardIdentifier | tail -c5) mcc=$(prop SimManager MobileCountryCode) mnc=$(prop SimManager MobileNetworkCode)"
  echo "== network: name=$(prop NetworkRegistration Name) mcc=$(prop NetworkRegistration MobileCountryCode) mnc=$(prop NetworkRegistration MobileNetworkCode)"
  # ☠️ VoiceCapable/SmsCapable are NOT measurements: ofono-binder-plugin-ext-qti
  # sets both flags unconditionally in qti_ims_iface_init(), so they read true on
  # every device that loads the plugin. Recorded once here, labelled, never sampled.
  echo "== ims:     Registered=$(prop IpMultimediaSystem Registered)   (VoiceCapable/SmsCapable omitted: compile-time constants)"
  echo "== rat pref: $(prop RadioSettings TechnologyPreference)   imsradio netdevs: $(imsdev)"
} > "$OUT"

END=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$END" ]; do
    printf '%s tech=%s reg=%s imsreg=%s imsdev=%s states=%s\n' \
        "$(date '+%T')" \
        "$(prop NetworkRegistration Technology)" \
        "$(prop NetworkRegistration Status)" \
        "$(prop IpMultimediaSystem Registered)" \
        "$(imsdev)" \
        "$(callstates)" >> "$OUT"
    sleep 1
done
echo "== ut-callwatch2 done $(date '+%F %T')" >> "$OUT"
