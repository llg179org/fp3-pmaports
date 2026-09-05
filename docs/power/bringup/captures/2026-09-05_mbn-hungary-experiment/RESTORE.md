# How to put this phone back — write this BEFORE changing anything

Before-state captured 2026-09-05T12:57:41+02:00, pmOS `7.1.3-postmarketos-qcom-msm8953` (the phone; an earlier draft of this line captured the HOST kernel by running uname in the wrong shell), full
listing in `before-state.txt`. The modem was running the generic config:

    Description: ROW_Commercial
    Status:      Active
    ID:          5C:F9:CA:DA:5C:35:85:17:BA:3B:B8:88:D0:34:2B:79:BD:5F:AD:ED

**To restore it:**

```sh
fp3-ssh "echo \$PW | sudo -S qmicli -d qrtr://0 \
    --pdc-activate-config=software,5C:F9:CA:DA:5C:35:85:17:BA:3B:B8:88:D0:34:2B:79:BD:5F:AD:ED"
# then confirm:
fp3-ssh "echo \$PW | sudo -S qmicli -d qrtr://0 --pdc-list-configs=software" | grep -B4 Active
```

☠️ **Activating is what makes a config current; loading only adds it to the
list.** So a restore is an activate of the id above, not a delete of anything —
and the Hungarian config may be left loaded and inactive without effect.

☠️ This file exists because the authorisation to change the modem was bounded by
the word *reversible*, and reversible means a recorded before-state, not a
belief that one could be reconstructed.
