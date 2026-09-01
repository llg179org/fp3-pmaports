#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# AI-generated (Claude Opus 5) under the direction of Lajoshazi, Laszlo Gergely.
"""The ONE reader for the RPM per-master XO statistics on msm8953.

WHY THIS FILE EXISTS
====================
Four separate ad-hoc readers of this same counter have shipped in this tree, and
every one of them was wrong in the same way: it printed a confident number
instead of failing.

    1. the tick        - duration/19200 is milliseconds, not microseconds
    2. the INT_MAX clamp - the device awk's printf "%d" turns 407012504635 into
                         2147483647, which read as a flawless 100.0 % duty
    3. the missing strtonum - the device awk defines and() but not strtonum, and
                         an undefined function aborts the whole awk mid-pipeline,
                         printing an EMPTY table that reads as "no traffic"
    4. '@' versus ':'  - mainline writes "Last XO shutdown enter @ N" and the
                         parser looked for ':', so a master that was DOWN was
                         printed as AWAKE

None of those is exotic. They keep happening because every tool re-derives the
parse. So: this module is the only place that is allowed to read the counter,
and `selftest-rpm-readers.sh` fails the build if another tool greps it directly.

THE TWO FORMATS
===============
mainline (msm8953-mainline, debugfs qcom_rpm_master_stats/<MASTER>), DECIMAL,
and note that the static fields use '@' while the accumulators use ':':

    MPSS:
        Last XO shutdown enter @ 202639006494
        Last XO shutdown exit @ 202634437695
        XO total duration: 407012504635
        XO shutdown count: 1234

downstream (the Ubuntu Touch oracle, /d/rpm_master_stats), HEX, and it carries
two fields mainline does not - `numshutdowns` and `active_cores`:

    MPSS
        xo_last_entered_at:0x1C8A1493A
        xo_accumulated_duration:0x169DFDF2A
        xo_count:0x46c
        active_cores:0x0

THE INVERSION TRAP, AND THE RULE THAT GETS OUT OF IT
====================================================
The XO duration counter is EDGE-UPDATED: it advances when a master EXITS XO
shutdown (measured, captures/2026-08-31_xo-dur-semantics). So over any window:

    a master that stayed DOWN the whole time   -> delta 0, count delta 0
    a master that stayed AWAKE the whole time  -> delta 0, count delta 0

They are byte-identical in the accumulators. Reading the first as the second is
the single most expensive mistake this tree has made. The static fields
disambiguate them and this module ALWAYS applies the rule:

    enter > exit                  -> the master is currently DOWN
    enter < exit                  -> the master is currently UP
    active_cores == 0 (downstream only) -> corroborates DOWN

A zero delta with the master DOWN means "asleep the whole window", and this
module reports it as such. A zero delta with the master UP means "awake the whole
window". A zero delta with NO static fields to decide is reported as UNDECIDABLE
and never as a duty.
"""
import re
import sys

TICK_HZ = 19_200_000          # the 19.2 MHz XO, not the sleep clock
MASTERS = ("APSS", "MPSS", "LPASS", "PRONTO")

# mainline: "<label> @ <dec>" for the static fields, "<label>: <dec>" for the rest
_ML = {
    "enter": re.compile(r"Last XO shutdown enter\s*@\s*(\d+)"),
    "exit":  re.compile(r"Last XO shutdown exit\s*@\s*(\d+)"),
    "dur":   re.compile(r"XO total duration\s*:\s*(\d+)"),
    "count": re.compile(r"XO shutdown count\s*:\s*(\d+)"),
}
# mainline carries the bitmask too, in hex, under a different name
_ML_CORES = re.compile(r"Active cores bitmask\s*:\s*0x([0-9a-fA-F]+)")
# downstream: "<key>:0x<hex>"
_DS = {
    "enter": re.compile(r"xo_last_entered_at\s*:\s*0x([0-9a-fA-F]+)"),
    "exit":  re.compile(r"xo_last_exited_at\s*:\s*0x([0-9a-fA-F]+)"),
    "dur":   re.compile(r"xo_accumulated_duration\s*:\s*0x([0-9a-fA-F]+)"),
    "count": re.compile(r"xo_count\s*:\s*0x([0-9a-fA-F]+)"),
    "cores": re.compile(r"active_cores\s*:\s*0x([0-9a-fA-F]+)"),
}


class Record:
    """One master's counters at one instant."""

    def __init__(self, name, enter, exit_, dur, count, cores=None, fmt=None):
        self.name = name
        self.enter = enter
        self.exit = exit_
        self.dur = dur          # XO ticks accumulated
        self.count = count      # shutdown count
        self.cores = cores      # downstream only; None on mainline
        self.fmt = fmt

    @property
    def down(self):
        """True/False if the static fields decide, None if they cannot.

        `enter > exit` means the last thing that happened was an ENTRY into XO
        shutdown, so the master is down right now.
        """
        if self.enter is None or self.exit is None:
            return None
        if self.enter == 0 and self.exit == 0:
            # never shut down since boot: awake, unless the counters say
            # otherwise (they do not - a master that had slept would have
            # non-zero timestamps)
            return False
        if self.enter == self.exit:
            return None
        return self.enter > self.exit

    def __repr__(self):
        d = {True: "down", False: "up", None: "?"}[self.down]
        return ("Record(%s dur=%d count=%d enter=%d exit=%d cores=%s state=%s)"
                % (self.name, self.dur, self.count, self.enter or 0,
                   self.exit or 0, self.cores, d))


def _grab(block, table, base):
    out = {}
    for key, rx in table.items():
        m = rx.search(block)
        out[key] = int(m.group(1), base) if m else None
    return out


def parse(text):
    """Parse one dump of one or more masters. Returns {name: Record}.

    Accepts either format, a single master's file, or several concatenated -
    which is what `for m in APSS MPSS LPASS PRONTO; do cat $M/$m; done` produces
    and what every capture in this tree stores.
    """
    out = {}
    # split on a line that is (or starts with) a master name
    positions = []
    # A leading tag is tolerated: modem-window.sh prefixes every line with
    # "BEFORE "/"AFTER ", and several captures in this tree are stored that way.
    for m in re.finditer(r"^[^\n]*?\b(%s)\s*:?[ \t]*$" % "|".join(MASTERS),
                         text, re.MULTILINE):
        positions.append((m.group(1), m.start()))
    if not positions:
        return out
    for i, (name, start) in enumerate(positions):
        end = positions[i + 1][1] if i + 1 < len(positions) else len(text)
        block = text[start:end]
        if "xo_accumulated_duration" in block:
            f = _grab(block, _DS, 16)
            fmt = "downstream"
        else:
            f = _grab(block, _ML, 10)
            mc = _ML_CORES.search(block)
            f["cores"] = int(mc.group(1), 16) if mc else None
            fmt = "mainline"
        if f["dur"] is None and f["count"] is None:
            continue
        out[name] = Record(name, f["enter"], f["exit"], f["dur"] or 0,
                           f["count"] or 0, f.get("cores"), fmt)
    return out


def split_prefixed(text, prefix):
    """Pull out the lines a tagged dump marks with `prefix` and strip the tag.

    `modem-window.sh` writes both ends of a window into ONE file, each line
    prefixed "BEFORE " or "AFTER ". Splitting that by hand is exactly the kind
    of per-tool re-derivation this module exists to stop.
    """
    out = []
    for line in text.splitlines():
        if line.startswith(prefix + " ") or line == prefix:
            out.append(line[len(prefix):].lstrip(" "))
        elif line.startswith(prefix + "\t"):
            out.append(line[len(prefix):])
    return "\n".join(out)


class Window:
    """The difference between two Records of the same master."""

    def __init__(self, before, after, seconds):
        assert before.name == after.name
        self.name = before.name
        self.before = before
        self.after = after
        self.seconds = float(seconds)
        self.d_ticks = after.dur - before.dur
        self.d_count = after.count - before.count

    @property
    def verdict(self):
        """'measured' | 'asleep' | 'awake' | 'undecidable'.

        This is the whole point of the module: a zero delta is NOT a duty.
        """
        if self.d_ticks > 0 or self.d_count > 0:
            return "measured"
        # nothing moved: the static fields decide which world this is
        b, a = self.before.down, self.after.down
        if b is True and a is True:
            return "asleep"
        if b is False and a is False:
            return "awake"
        return "undecidable"

    @property
    def off_s(self):
        """Seconds spent in XO shutdown during the window, or None."""
        v = self.verdict
        if v == "measured":
            return self.d_ticks / TICK_HZ
        if v == "asleep":
            return self.seconds
        if v == "awake":
            return 0.0
        return None

    @property
    def duty(self):
        """Fraction of the window the master was AWAKE, or None if undecidable."""
        off = self.off_s
        if off is None:
            return None
        return max(0.0, min(1.0, 1.0 - off / self.seconds))

    @property
    def wakes_per_s(self):
        return self.d_count / self.seconds if self.d_count else 0.0

    @property
    def ms_per_wake(self):
        if not self.d_count:
            return None
        awake_s = self.seconds - (self.off_s or 0.0)
        return 1000.0 * awake_s / self.d_count

    def line(self):
        v = self.verdict
        if v == "undecidable":
            return ("%-7s UNDECIDABLE - zero delta and the static fields do not "
                    "decide; this is NOT a duty" % self.name)
        if v == "asleep":
            return ("%-7s asleep for the whole window (zero delta, enter>exit at "
                    "both ends), 0 wakes" % self.name)
        if v == "awake":
            return ("%-7s awake for the whole window (zero delta, never entered "
                    "XO shutdown), 0 wakes" % self.name)
        mw = self.ms_per_wake
        return ("%-7s %5.1f %% awake  %6.2f wakes/s  %s"
                % (self.name, 100.0 * self.duty, self.wakes_per_s,
                   ("%.1f ms/wake" % mw) if mw is not None else "-"))


def window(before_text, after_text, seconds):
    """{name: Window} for every master present in both dumps."""
    b, a = parse(before_text), parse(after_text)
    return {n: Window(b[n], a[n], seconds) for n in b if n in a}


def _main(argv):
    if len(argv) >= 2 and argv[1] == "--parse":
        for name, rec in parse(open(argv[2], encoding="utf-8",
                                    errors="replace").read()).items():
            print(rec)
        return 0
    if len(argv) >= 4 and argv[1] == "--tagged":
        # one modem-window.sh-style file with BEFORE/AFTER tags
        raw = open(argv[2], encoding="utf-8", errors="replace").read()
        ws = window(split_prefixed(raw, "BEFORE"),
                    split_prefixed(raw, "AFTER"), float(argv[3]))
        if not ws:
            print("no master found in both halves", file=sys.stderr)
            return 1
        for n in MASTERS:
            if n in ws:
                print(ws[n].line())
        return 0
    if len(argv) >= 5 and argv[1] == "--window":
        before = open(argv[2], encoding="utf-8", errors="replace").read()
        after = open(argv[3], encoding="utf-8", errors="replace").read()
        ws = window(before, after, float(argv[4]))
        if not ws:
            print("no master found in both dumps", file=sys.stderr)
            return 1
        for n in MASTERS:
            if n in ws:
                print(ws[n].line())
        return 0
    print(__doc__.strip().splitlines()[0])
    print("usage: rpm_master_stats.py --parse FILE")
    print("       rpm_master_stats.py --window BEFORE AFTER SECONDS")
    print("       rpm_master_stats.py --tagged FILE SECONDS   "
          "(one modem-window.sh file with BEFORE/AFTER tags)")
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
