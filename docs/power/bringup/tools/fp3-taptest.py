#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""fp3-taptest - a touch target that cannot move, and a log of what a client got.

☠️ WHY THERE IS NO LAYOUT HERE. The first four versions used ordinary GTK
containers and the split kept shifting the moment the operator touched it -
hiding the instructions re-laid out the window, a wrapped label's natural size
grew with its text, a Grid took its natural width instead of filling. Each fix
uncovered the next one. A target that moves while it is being tapped measures
the operator's aim, not the device, and on 2026-09-06 it manufactured a run of
eleven "lost" taps that were nothing of the kind.

So there is one DrawingArea covering the window and every region is arithmetic
on its width and height. Nothing can reflow because there is nothing to reflow.

Regions, top to bottom:
  0    .. 4/8 h   the record: instructions until the first tap, then the marks
  4/8  .. 5/8 h   MARK - press it when a tap felt lost
  5/8  .. h       the target: left half '.', right half 'o', no gap anywhere

Tapping the halves alternately writes ". o . o"; a lost tap shows as ".." or
"oo" with no counting and no aiming. A repeat is logged BY THE APP as a BREAK
with its run length, because expecting the operator to notice one is how the
early rounds were lost.

/home/fp3/taptest.log gets every event to the millisecond. That is the client
side of the compositor; the touch driver's own log is the kernel side. A tap in
one and not the other says which layer lost it - the question no earlier
instrument here could answer.

HOW TO RUN IT
=============
On the device, as a unit so it survives the ssh session that started it:

    systemd-run --unit=fp3-taptest --collect --uid=10000 \
      --setenv=XDG_RUNTIME_DIR=/run/user/10000 \
      --setenv=WAYLAND_DISPLAY=wayland-0 --setenv=GDK_BACKEND=wayland \
      --setenv=HOME=/home/fp3 /usr/bin/python3 /tmp/fp3-taptest.py

☠️ Launched with `setsid ... &` over ssh it dies when the session closes - it
did, after drawing its first frame, and the log looked like a crash.

☠️ RUN kernel-contacts.py AT THE SAME TIME. This app is BLIND on its own.
--------------------------------------------------------------------------
It only sees what the compositor hands it, so a touch that never arrives leaves
NOTHING in its log - and "the finger did not land" and "the panel or the driver
never reported it" are then indistinguishable. The second is the fault this
port exists to find. So:

    systemd-run --unit=fp3-kcontacts --collect /usr/bin/python3 \
        /tmp/kernel-contacts.py /dev/input/event4 /var/log/kernel-contacts.log

That logs the start of every contact straight off evdev, with the kernel's own
timestamp. A second reader is safe: evdev gives each open file its own ring.

HOW TO READ THE TWO LOGS TOGETHER
=================================
Line up `CONTACT` (kernel) against `RAW touch-begin` (this app) by timestamp;
they should pair within a few ms. Then:

  kernel CONTACT, no RAW      -> lost between evdev and the client
                                 (libinput or phoc). THE INTERESTING CASE.
  RAW, no tap                 -> lost in GTK. Measured 2026-09-06: 18 of 560,
                                 every one with a second finger already down,
                                 which is why taps now come from the raw touch
                                 and GestureClick is only a control.
  no CONTACT and no RAW       -> nothing reached the input layer at all. Either
                                 the finger really did not land, or the panel /
                                 driver dropped it before evdev - and only the
                                 i2c and interrupt evidence separates those.

Counting rules that have each cost a wrong conclusion here:

  * Compare `raw` and `gest` in the header. A gap between them IS lost taps.
    A BREAK is NOT: it only says the alternation broke, which a deliberate
    double-tap on one side does too.
  * Exclude raw touches with y < 4/8 of the height. That area is the record and
    is not a target, and counting them as losses was a false positive once.
  * `SYN_DROPPED` in the kernel log means that reader fell behind and its
    counts after it are incomplete. The ring is 1024 events here, about 70
    one-finger taps.
  * A `draw->present` sample of 0 has no presentation time; do not average it
    in, and do not compare it against the prediction - 0 == 0 read as agreement
    once and nearly retracted a good measurement.
"""
import atexit
import math
import os
import queue
import signal
import struct
import subprocess
import threading
import wave

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib
import time

LOG = "/home/fp3/taptest.log"
MARK_TOP, HALVES_TOP = 4.0 / 8.0, 5.0 / 8.0
MAX_MARKS = 600
# ☠️ These must fit the RECORD AREA - the top 4/8 of the window, 360x180
# logical px on this phone. Written longer once and they overran onto the MARK
# bar and past the right edge: at font 11 the width is about 44 characters and
# there is room for about 20 lines. Check a screenshot after editing them.
INSTRUCTIONS = [
    "Tap the two lower halves ALTERNATELY.",
    "Press MARK when a tap felt lost.",
    "",
    "EACH ROW IS A COUNTER for one layer:",
    " irq      the CHIP raised its interrupt",
    " contact  the DRIVER delivered a touch",
    " raw      it reached THIS APP (via phoc)",
    " gest     GTK turned it into a click",
    " tap      the app recorded it",
    " shown    a frame reached the screen",
    "",
    "The six cells are the last six SECONDS.",
    "A cell is GREEN when that layer saw the",
    "SAME number as the layer it comes from,",
    "RED when it saw FEWER - that cell is the",
    "hop that dropped them, and when.",
    "irq and shown are NOT one per touch, so",
    "they are counts only, never judged red -",
    "except contact, which goes RED if irq",
    "moved and no touch came out of it.",
    "0 in the record = a 2-finger overlap.",
    "Tap this text to CLEAR the record.",
]



# One evdev record on 64-bit: tv_sec, tv_usec, type, code, value.
EV_FMT = "qqHHi"
EV_SZ = struct.calcsize(EV_FMT)
EV_ABS, ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x03, 0x2f, 0x39
EV_SYN, SYN_DROPPED = 0x00, 3
IRQ_NAME = "hx83112b"


def _irq_count():
    """The touch controller's interrupt count, or None.

    The chip raising its interrupt means "there is touch data" - it is the
    earliest thing on this phone that can be observed at all. ☠️ It is NOT one
    interrupt per tap: a press, its moves and its release are many, so this is
    only ever read as "did it move", never as a tap count.
    """
    try:
        for line in open("/proc/interrupts"):
            if IRQ_NAME in line:
                return sum(int(x) for x in line.split(":")[1].split()[:8])
    except (OSError, ValueError, IndexError):
        pass
    return None


# ---------------------------------------------------------------------------
# Audible feedback, added 2026-09-08 at the operator's request.
#
# WHY. On 2026-09-08 05:41 the operator's hand drifted left over ~6 s until the
# left finger left the digitizer entirely; 1.589 s and about seven taps
# produced NOTHING - no contact, no interrupt - because a finger outside the
# sensor generates nothing to lose. Every layer of this instrument was blind to
# it, and the drift was plainly visible in the x column six seconds before it
# mattered. Nobody was watching that column, and a finger cannot feel where the
# digitizer ends. So the instrument now says it out loud.
#
#   EDGE  432 Hz            a tap landed inside a margin: any of the four
#                           outer edges, either side of the vertical split, or
#                           either side of the field's top boundary
#   MISS  864 Hz (= 432*2)  the alternation broke, i.e. a tap may have been lost
#
# ☠️ BOTH WERE ONE OCTAVE LOWER AND THE LOW ONE DID NOT ARRIVE. The first
# version used 216 Hz for EDGE and 432 Hz for MISS; the operator reported the
# 216 as "sokkal halkabb" - much quieter - than the 432, which is the phone
# micro-speaker's rolloff below roughly 400-800 Hz, measured by ear rather than
# assumed. Both were doubled at their request, preserving the octave between
# them. The lesson is not about these numbers: a tone the transducer cannot
# reproduce is a detector that silently never reports, so pick the frequency
# against the SPEAKER and confirm it by ear before trusting the channel. Every
# beep is also written to the log, which stays the authoritative record.
#
# ☠️ AND AUDIO IS NOT FREE AS AN INSTRUMENT. Playing a tone wakes LPASS, the
# SLIMbus link and the WCD9335 codec. That does not touch the input path, which
# is interrupt-driven and independent of it - but it makes this app unsuitable,
# while beeping, for any power, idle-residency or suspend measurement. Turn the
# beeps off (BEEP_ENABLED = False) before using it for one.
TONE_EDGE_HZ, TONE_EDGE_MS = 432.0, 90
TONE_MISS_HZ, TONE_MISS_MS = 864.0, 150
# ☠️ THE BOTTOM FRAME SITS HIGHER THAN THE OTHER THREE, on the operator's
# instruction. It is not symmetry that matters here but where the hand actually
# leaves: the bottom of this panel carries the gesture strip and the chin, so a
# drift downwards runs out of sensor sooner than a drift sideways does. A single
# margin would either be too tight at the bottom or needlessly loud on the sides.
EDGE_MARGIN = 25          # left / right / top; the 05:41 drift was flagged by x < 29
EDGE_MARGIN_BOTTOM = 60   # bottom only - the frame raised, as asked
# ☠️ The vertical split is an edge too, and a more treacherous one, because
# crossing it does not lose the tap - it files it on the WRONG SIDE. That reads
# in the record as a BREAK, i.e. as a lost tap, which is the one failure this
# instrument exists to measure. So both sides of the divider warn.
DIVIDER_MARGIN = 20       # either side of the vertical line
# ☠️ And the same argument applies to the HORIZONTAL boundary where the halves
# meet the MARK bar. A tap meant for a half that lands slightly high does not
# vanish - it is recorded as a MARK, i.e. as the operator reporting a lost tap.
# That is worse than losing it: it puts a false entry into the very record the
# lost taps are counted from. So this line warns on both sides too.
HALVES_TOP_MARGIN = 20    # either side of the halves/MARK boundary
EDGE_REPEAT_S = 0.30      # rate limit, so edge tapping does not become a buzz
MISS_REPEAT_S = 0.15
BEEP_ENABLED = True


def _render_tone(path, hz, ms, rate=48000, amp=0.5):
    """Write a mono 16-bit WAV of one sine, with 5 ms raised-cosine edges.

    The fades are not decoration: a tone that starts and stops at full
    amplitude clicks, and a click is broadband - it would be audible where the
    tone itself is not, which would make the low beep look like it worked.
    """
    n = int(rate * ms / 1000.0)
    fade = max(1, int(rate * 0.005))
    frames = bytearray()
    for i in range(n):
        env = 1.0
        if i < fade:
            env = 0.5 - 0.5 * math.cos(math.pi * i / fade)
        elif i > n - fade - 1:
            env = 0.5 - 0.5 * math.cos(math.pi * (n - 1 - i) / fade)
        v = int(32767 * amp * env * math.sin(2.0 * math.pi * hz * i / rate))
        frames += struct.pack("<h", max(-32768, min(32767, v)))
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(bytes(frames))
    return path


class Beeper:
    """Plays a tone WITHOUT touching the GTK main loop.

    ☠️ The whole point is that this must not sit in the input path. The
    operator asked whether it could run on a parallel thread so it does not
    slow the sampling; the honest answer is in two halves. The KERNEL's touch
    path cannot be slowed by anything here - it is interrupt-driven, there is
    no poll_interval on the input device, and nothing samples the panel. What
    CAN be slowed is this app's own main loop, and that is what the thread is
    for: the handler only drops a name into a queue and returns.

    ☠️ maxsize=1 with a non-blocking put is deliberate. An unbounded queue
    turns a burst of edge taps into a backlog of beeps that arrive seconds
    late, describing a moment that has passed - feedback that lies about WHEN.
    Dropping is the correct behaviour; the log keeps the count either way.
    """

    def __init__(self, log, dirpath="/tmp"):
        self._log = log
        self.ok = False
        self.dropped = 0
        self.played = 0
        self._last = {}
        self._q = queue.Queue(maxsize=1)
        self._player = None
        for cand in ("paplay", "pw-play", "aplay"):
            if _which(cand):
                self._player = cand
                break
        if self._player is None or not BEEP_ENABLED:
            self._log("  beeper: DISABLED (%s)"
                      % ("no player found" if self._player is None else "BEEP_ENABLED false"))
            return
        try:
            self._files = {
                "edge": _render_tone(os.path.join(dirpath, "fp3-tone-edge.wav"),
                                     TONE_EDGE_HZ, TONE_EDGE_MS),
                "miss": _render_tone(os.path.join(dirpath, "fp3-tone-miss.wav"),
                                     TONE_MISS_HZ, TONE_MISS_MS),
                # ☠️ The sink is SUSPENDED when idle, so the FIRST tone pays for
                # waking LPASS and the codec and can be clipped or lost. A
                # silent primer at startup pays that cost once, before any
                # measurement, instead of inside the first event that matters.
                "prime": _render_tone(os.path.join(dirpath, "fp3-tone-prime.wav"),
                                      TONE_MISS_HZ, 60, amp=0.0),
            }
        except OSError as e:
            self._log("  beeper: DISABLED (cannot write tones: %s)" % e)
            return
        self.ok = True
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()
        self._q.put_nowait("prime")
        # ☠️ Report EVERY margin, not just the first. A line reading
        # "margin 25 px" next to a bottom margin of 60 and a divider band of
        # 20 is a false record of the configuration, and the log is what a
        # reader trusts months later when the constants have moved on.
        self._log("  beeper: %s, edge %.0f Hz/%d ms, miss %.0f Hz/%d ms; "
                  "margins: sides/top %d px, bottom %d px, divider +-%d px, "
                  "field-top +-%d px"
                  % (self._player, TONE_EDGE_HZ, TONE_EDGE_MS,
                     TONE_MISS_HZ, TONE_MISS_MS,
                     EDGE_MARGIN, EDGE_MARGIN_BOTTOM, DIVIDER_MARGIN,
                     HALVES_TOP_MARGIN))

    def _run(self):
        while True:
            name = self._q.get()
            path = self._files.get(name)
            if not path:
                continue
            try:
                subprocess.run([self._player, path],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=4)
                self.played += 1
            except Exception:
                pass

    def fire(self, name, gap):
        """Queue a tone. Returns True if queued, False if rate-limited/dropped."""
        if not self.ok:
            return False
        now = time.time()
        if now - self._last.get(name, 0.0) < gap:
            return False
        self._last[name] = now
        try:
            self._q.put_nowait(name)
            return True
        except queue.Full:
            self.dropped += 1
            return False


def _which(cmd):
    for d in os.environ.get("PATH", "/usr/bin:/bin").split(":"):
        f = os.path.join(d, cmd)
        if os.path.isfile(f) and os.access(f, os.X_OK):
            return f
    return None


KCONTACTS_UNIT = "fp3-kcontacts"
KCONTACTS_LOG = "/var/log/kernel-contacts.log"


def _touch_event_node():
    """Find the touchscreen's /dev/input/eventN, rather than hardcoding it.

    ☠️ The number is not stable: it depends on probe order, and a run pointed at
    the wrong node would log an empty kernel side that reads exactly like a
    panel that reported nothing.
    """
    try:
        block = ""
        for para in open("/proc/bus/input/devices").read().split("\n\n"):
            if "imax" in para or "hx83" in para:
                block = para
                break
        for line in block.splitlines():
            if line.startswith("H: Handlers"):
                for tok in line.split("=", 1)[1].split():
                    if tok.startswith("event"):
                        return "/dev/input/" + tok
    except OSError:
        pass
    return None


def _unit_state(unit):
    try:
        return subprocess.run(["systemctl", "show", "-p", "ActiveState",
                               "--value", unit], capture_output=True,
                              text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def start_kcontacts(log):
    """Start the kernel-side contact reader unless something already runs it.

    Returns True only if WE started it - the caller must not stop a unit it did
    not start, because a longer measurement may be using it.
    """
    if _unit_state(KCONTACTS_UNIT) in ("active", "activating"):
        log("kernel-contacts: already running, left alone")
        return False
    node = _touch_event_node()
    if not node:
        log("kernel-contacts: NOT started - no touchscreen event node found. "
            "The kernel side of this run is MISSING, not empty.")
        return False
    here = os.path.dirname(os.path.abspath(__file__))
    reader = os.path.join(here, "kernel-contacts.py")
    if not os.path.exists(reader):
        reader = "/tmp/kernel-contacts.py"
    if not os.path.exists(reader):
        log("kernel-contacts: NOT started - %s missing. The kernel side of "
            "this run is MISSING, not empty." % reader)
        return False
    cmd = ["sudo", "-n", "systemd-run", "--unit=" + KCONTACTS_UNIT, "--collect",
           "/usr/bin/python3", reader, node, KCONTACTS_LOG]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as e:
        log("kernel-contacts: NOT started (%s). The kernel side of this run "
            "is MISSING, not empty." % e)
        return False
    if r.returncode != 0:
        log("kernel-contacts: NOT started, rc=%d %s. The kernel side of this "
            "run is MISSING, not empty."
            % (r.returncode, (r.stderr or "").strip()[:120]))
        return False
    log("kernel-contacts: started on %s -> %s" % (node, KCONTACTS_LOG))
    return True


def stop_kcontacts(log):
    try:
        subprocess.run(["sudo", "-n", "systemctl", "stop", KCONTACTS_UNIT],
                       capture_output=True, timeout=20)
        log("kernel-contacts: stopped (we started it)")
    except (OSError, subprocess.SubprocessError) as e:
        log("kernel-contacts: stop FAILED (%s) - it may still be running" % e)


def _ms(v):
    return "n/a" if v is None else "%.1f ms" % v


def _stage_colour(v, warn, bad):
    """Green below warn, amber below bad, red above; grey when unmeasurable."""
    if v is None:
        return (0.35, 0.35, 0.38)
    if v < warn:
        return (0.25, 0.80, 0.40)
    if v < bad:
        return (0.95, 0.80, 0.25)
    return (0.90, 0.25, 0.25)


class TapTest(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="fp3-taptest")
        self.fullscreen()
        self.marks, self.n_dot, self.n_o = [], 0, 0
        self.n_edge = 0
        self.beeper = None   # built after the log is open, below
        self.breaks = self.n_mark = self.run_len = 0
        self.last = None
        self.started = False
        self.n_draw = 0
        self.n_gesture = 0
        self.touch_seen = False
        self.n_down = 0
        self.mark_flash_until = 0.0
        # ☠️ The halves had NO feedback of their own: a tap changed one 16 px
        # character at the end of a dense block of identical .o.o.o and nothing
        # else, so a press that registered perfectly looked like one that had
        # not. On 2026-09-06 that alone produced the report "the character only
        # appeared when I pressed MARK" - MARK flashes, the halves did not.
        # Measured in the same run: press to draw is 1.0 ms median. The app was
        # never late; it was invisible.
        self.half_flash_until = 0.0
        self.half_flash_side = None
        self.tap_xy = None

        # ── the five stages of one tap ────────────────────────────────────
        # Filled in as the tap travels; drawn as four fixed blocks so a slow
        # stage is a colour, not a number to read. All times CLOCK_MONOTONIC ms.
        #   t_evt   the compositor's own stamp on the event  (event.get_time())
        #   t_raw   EventControllerLegacy handler ran        -> transport
        #   t_ges   GestureClick::pressed ran                -> arbitration
        #   t_drw   _draw ran                                -> render schedule
        #   t_prs   FrameTimings.get_presentation_time()     -> ON THE PANEL
        self.stage = {}
        self.stage_hist = []
        self.stage_counts = {}
        self.pending_frame = None      # (frame_counter, stage dict)
        self.evt_offset = None         # GdkEvent clock -> CLOCK_MONOTONIC
        self.evt_offset_ok = None
        self.log = open(LOG, "a", buffering=1)
        self._log("== taptest start %s" % time.strftime("%F %H:%M:%S"))
        # ☠️ AFTER the log is open, not before. Built at the top of __init__ it
        # announced itself through self._logline into a self.log that did not
        # exist yet, and the whole app died in its constructor - measured
        # 2026-09-08 06:22, unit up for three seconds. Anything that reports
        # for itself has to be created after the thing it reports into.
        self.beeper = Beeper(self._logline)

        # ☠️ This app is blind below the compositor, so the kernel-side reader
        # is not optional - a run without it cannot tell "the finger did not
        # land" from "the panel never reported it". Start it here rather than
        # relying on the operator remembering, and stop it on the way out ONLY
        # if we were the ones who started it: another measurement may own it.
        self.owns_kcontacts = start_kcontacts(self._logline)

        # ☠️ Watch evdev IN THIS PROCESS as well as in the external reader. The
        # external log is the independent witness; this one is what lets the
        # kernel's own layers appear on screen next to the client's, so a
        # contact that never becomes a GdkEvent is visible AS IT HAPPENS rather
        # than in a diff afterwards. Two readers are safe - evdev gives every
        # open file its own ring buffer.
        self.n_contact = self.n_syn_dropped = 0
        self.contact_mono = None
        self.mt_slot = 0
        # ── the per-layer counters and their one-second windows ───────────
        # ☠️ THE CHAIN THAT MUST MATCH IS contact -> raw -> gest -> tap, and
        # ONLY that. Those are one event each per touch. The interrupt count is
        # NOT: a press, its moves and its release are many, so comparing it
        # would paint red in every window and teach the operator to ignore the
        # colour. It is shown as a count and never judged.
        self.win = []                 # list of dicts: one closed 1 s window
        self.win_prev = None          # counter snapshot at the window start
        self.n_tap = 0
        self.n_shown = 0
        self.irq0 = _irq_count()
        self.irq_now = self.irq0
        self.n_irq_step = 0
        self._open_evdev()
        GLib.timeout_add(500, self._poll_irq)
        GLib.timeout_add(1000, self._close_window)
        atexit.register(self._cleanup)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, self._on_signal)

        self.area = Gtk.DrawingArea()
        self.area.set_draw_func(self._draw)
        self.set_child(self.area)

        g = Gtk.GestureClick()
        g.set_button(0)                      # any button, and touch
        g.connect("pressed", self._pressed)
        self.area.add_controller(g)

        # ☠️ A SECOND, RAW counter, because GestureClick is itself a gesture
        # recogniser: it can reject a touch it decides was the start of a drag,
        # and in the log that is indistinguishable from the compositor never
        # delivering it. EventControllerLegacy sees the GdkEvent before any
        # gesture arbitration, so the pair splits the remaining unknown in two:
        #
        #   kernel CONTACT  ->  RAW  : lost in libinput or phoc
        #   RAW  ->  tap          : lost in GTK's gesture recognition
        #
        # Without it "the client did not receive it" covers both, and this
        # investigation spent an afternoon unable to tell them apart.
        raw = Gtk.EventControllerLegacy()
        # ☠️ Without CAPTURE this controller saw NOTHING - `raw 0` in the header
        # for every run on 2026-09-06, and both transport stages reported n/a.
        # Controllers default to the BUBBLE phase, where GestureClick has
        # already claimed the sequence. CAPTURE runs first, which is the whole
        # point of having a raw counter next to a gesture one.
        raw.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        raw.connect("event", self._raw_event)
        self.area.add_controller(raw)
        self.n_raw = 0

        GLib.timeout_add(3000, self._geom_once)

    # ── logging ────────────────────────────────────────────────────────────
    def _log(self, line):
        self.log.write(line + "\n")

    def _open_evdev(self):
        node = _touch_event_node()
        if not node:
            self._logline("evdev watch: NO event node - the kernel rows will "
                          "stay GREY, which means unmeasured, not zero")
            return
        try:
            fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as e:
            self._logline("evdev watch: cannot open %s (%s) - the kernel rows "
                          "will stay GREY, which means unmeasured, not zero"
                          % (node, e))
            return
        self.evdev_fd = fd
        GLib.unix_fd_add_full(GLib.PRIORITY_DEFAULT, fd, GLib.IOCondition.IN,
                              self._on_evdev, None)
        self._logline("evdev watch: open on %s" % node)

    def _on_evdev(self, fd, _cond, _data):
        try:
            buf = os.read(fd, EV_SZ * 64)
        except (BlockingIOError, OSError):
            return True
        for off in range(0, len(buf) - EV_SZ + 1, EV_SZ):
            sec, usec, typ, code, val = struct.unpack_from(EV_FMT, buf, off)
            if typ == EV_SYN and code == SYN_DROPPED:
                self.n_syn_dropped += 1
                self._logline("evdev SYN_DROPPED #%d - OUR ring overflowed, "
                              "counts after this are incomplete"
                              % self.n_syn_dropped)
            elif typ == EV_ABS and code == ABS_MT_SLOT:
                self.mt_slot = val
            elif typ == EV_ABS and code == ABS_MT_TRACKING_ID and val >= 0:
                self.n_contact += 1
                self.contact_mono = self._mono()
                self._logline("CONTACT #%d  slot=%d  kernel-ts %d.%06d"
                              % (self.n_contact, self.mt_slot, sec, usec))
        return True

    def _counters(self):
        return {"irq": (self.irq_now or 0) - (self.irq0 or 0),
                "contact": self.n_contact,
                "raw": self.n_raw,
                "gest": self.n_gesture,
                "tap": self.n_tap,
                "shown": self.n_shown}

    def _close_window(self):
        # One second of deltas. ☠️ It does NOT repaint: a timer-driven repaint
        # is the self-perturbation that contaminated the first presentation
        # numbers. The cells appear at the next natural paint, and while
        # nothing is being tapped every delta is zero anyway.
        cur = self._counters()
        if self.win_prev is not None:
            d = {k: cur[k] - self.win_prev[k] for k in cur}
            if any(v for v in d.values()):
                self._log("%s  WINDOW  " % self._stamp()
                          + "  ".join("%s %d" % (k, d[k]) for k in
                                      ("irq", "contact", "raw", "gest", "tap",
                                       "shown")))
            self.win.append(d)
            del self.win[:-6]
        self.win_prev = cur
        return True

    def _poll_irq(self):
        # Reads a file every 500 ms and NEVER repaints. A repaint here would be
        # the same self-perturbation that contaminated the first presentation
        # numbers; the light steps at the next natural paint instead.
        c = _irq_count()
        if c is not None and self.irq_now is not None and c != self.irq_now:
            self.n_irq_step += 1
        self.irq_now = c
        return True

    def _logline(self, msg):
        self._log("%s  %s" % (self._stamp(), msg))

    def _cleanup(self):
        if getattr(self, "owns_kcontacts", False):
            self.owns_kcontacts = False
            stop_kcontacts(self._logline)
        b = getattr(self, "beeper", None)
        if b is not None and b.ok:
            self._log("  beeper: %d played, %d dropped, %d edge detections"
                      % (b.played, b.dropped, self.n_edge))
        self._log("== taptest stop %s" % time.strftime("%F %H:%M:%S"))
        try:
            self.log.flush()
        except ValueError:
            pass

    def _on_signal(self, _sig, _frm):
        # systemctl stop sends SIGTERM; without a handler the process dies
        # before atexit runs and the reader is left behind.
        self._cleanup()
        os._exit(0)

    @staticmethod
    def _mono():
        return time.clock_gettime(time.CLOCK_MONOTONIC) * 1000.0

    def _stamp(self):
        t = time.time()
        return "%s.%03d" % (time.strftime("%H:%M:%S", time.localtime(t)),
                            (t % 1) * 1000)

    def _geom_once(self):
        w, h = self.area.get_width(), self.area.get_height()
        if w and h:
            self._log("%s  geometry: %dx%d, halves %d + %d px, divider at %d"
                      % (self._stamp(), w, h, w // 2, w - w // 2, w // 2))
            return False
        return True

    # ── input ──────────────────────────────────────────────────────────────
    def _pressed(self, _g, _n, x, y):
        """GestureClick path. Kept for the raw->ges timing and as a control."""
        t = self._mono()
        self.n_gesture += 1
        if self.touch_seen:
            # ☠️ The raw touch already handled this tap. GestureClick is NOT the
            # tap source any more: measured 2026-09-06, 18 of 560 touches were
            # dropped by it and ALL 18 had a second finger already down - it
            # handles one sequence at a time, so alternating two fingers loses
            # every touch that lands before the previous one lifts. 542 taps
            # with one finger down, zero lost. The recogniser was the fault, not
            # the panel, the driver, libinput or the compositor.
            self.stage["raw_ges"] = (t - self.stage["t_raw"]
                                     if "t_raw" in self.stage else None)
            self.stage["t_ges"] = t
            return
        if "t_ges" in self.stage or "t_drw" in self.stage:
            self.stage = {}
        self.stage["t_ges"] = t
        self.stage["raw_ges"] = t - self.stage["t_raw"] if "t_raw" in self.stage else None
        self._handle_tap(x, y)

    def _handle_tap(self, x, y, fingers=1):
        """One tap, from whichever source saw it first. The stage record has
        already been opened by the caller."""
        w, h = self.area.get_width(), self.area.get_height()
        if not h:
            return
        # ☠️ EDGE FIRST, before any region dispatch. A tap that is about to
        # walk off the digitizer has to be announced wherever it landed - the
        # record area and the MARK bar reach the bezel too, and the 05:41 drift
        # would not have been caught by a check that only looked at targets.
        # The distance is to the nearest of ALL FOUR edges, as asked.
        cand = []
        if x < EDGE_MARGIN:
            cand.append(("left", x))
        if (w - x) < EDGE_MARGIN:
            cand.append(("right", w - x))
        if y < EDGE_MARGIN:
            cand.append(("top", y))
        if (h - y) < EDGE_MARGIN_BOTTOM:
            cand.append(("bottom", h - y))
        # ☠️ The divider only EXISTS below the field's top edge. Checked at any
        # y it fired for taps in the record area, where the split means nothing
        # and a tap wipes the record instead of picking a side - a false
        # warning, and one that would have trained the operator to ignore the
        # tone. Found by the case table below, not in use.
        dv = abs(x - w / 2.0)
        if y >= h * HALVES_TOP and dv < DIVIDER_MARGIN:
            cand.append(("divider", dv))
        dh = abs(y - h * HALVES_TOP)
        if dh < HALVES_TOP_MARGIN:
            cand.append(("field-top", dh))
        if cand:
            # Report the WORST of them, not the first: a corner is inside two
            # margins at once and naming only one would understate it.
            where, near = min(cand, key=lambda c: c[1])
            self.n_edge += 1
            fired = self.beeper.fire("edge", EDGE_REPEAT_S)
            # The beep is feedback; THIS LINE is the evidence. A tone that was
            # rate-limited, dropped, or simply inaudible on this speaker still
            # leaves the detection in the record, so "I heard nothing" and "it
            # did not fire" stay distinguishable. The side is logged because
            # the warning is directionless by ear - one tone for five
            # boundaries - and only the log says which one was approached.
            self._log("%s  EDGE #%d  %s  %.0f px  at %.0f,%.0f of %dx%d  beep=%s"
                      % (self._stamp(), self.n_edge, where.upper(), near,
                         x, y, w, h, "yes" if fired else "rate-limited"))
        if y < h * MARK_TOP:
            # Tapping the record clears it, so a long run can be cut into
            # readable stretches without restarting the app. ☠️ The COUNTERS
            # are deliberately left alone: they are the measurement, the
            # string is only its display, and resetting both would silently
            # discard the totals the header is there to keep.
            if self.started and self.marks:
                self._log("%s  CLEAR  (record wiped by a tap at %.0f,%.0f; "
                          "%d marks dropped, counters kept)"
                          % (self._stamp(), x, y, len(self.marks)))
                del self.marks[:]
                self.last = None
                self.run_len = 0
                self.area.queue_draw()
            return                            # the record area is not a target
        if y < h * HALVES_TOP:
            self.n_mark += 1
            self.marks.append("|")
            # ☠️ MARK had no feedback at all, so a press that registered
            # perfectly looked like one that had failed, and the operator
            # pressed again - four times in half a second on 2026-09-06. The
            # instrument was manufacturing the failures it was meant to record.
            self.mark_flash_until = time.time() + 0.35
            GLib.timeout_add(380, self._unflash)
            self._log("%s  MARK #%d  (operator felt a lost tap)"
                      % (self._stamp(), self.n_mark))
        else:
            sym = "." if x < w / 2 else "o"
            self.half_flash_until = time.time() + 0.20
            self.half_flash_side = sym
            self.tap_xy = (x, y)
            GLib.timeout_add(230, self._unflash)
            if sym == ".":
                self.n_dot += 1
            else:
                self.n_o += 1
            total = self.n_dot + self.n_o
            if sym == self.last:
                self.run_len += 1
                self.breaks += 1
                # ☠️ A BREAK is the only LIVE signal this app has that a tap
                # may have gone missing, and it is deliberately a weak one:
                # the app's own rules say a repeat also happens when the
                # operator taps one side twice on purpose. It is used here
                # because the alternative - a tap that produced no contact and
                # no interrupt - leaves nothing at all to trigger on. The tone
                # therefore means "the alternation just broke", not "a tap was
                # lost", and the log line below is what gets counted.
                fired = self.beeper.fire("miss", MISS_REPEAT_S)
                self._log("%s  BREAK  %s repeated, run=%d  (#%d)  x=%.0f/%d  beep=%s"
                          % (self._stamp(), sym, self.run_len + 1, total, x, w,
                             "yes" if fired else "rate-limited"))
            else:
                self.run_len = 0
            self.last = sym
            # ☠️ A touch that landed while another finger was still down takes
            # the place of its side symbol, it does not follow it: the record
            # stays one glyph per tap, so the sequence can still be read at a
            # glance and the alternation is still countable by eye. The side is
            # NOT lost - it is in the log line below, and in the . / o totals
            # in the header, which keep counting it.
            #
            # Every one of these was SILENTLY DROPPED by GestureClick until
            # 2026-09-06 (18 of 18), which is why they are marked at all. The
            # glyph is a zero because Adwaita Mono - the only mono font here
            # that does, checked by rendering it - draws it with a dot in the
            # middle, so it cannot be read as the 'o' of the right half.
            self.marks.append("0" if fingers >= 2 else sym)
            self.n_tap += 1
            self._log("%s  %s  #%d  x=%.0f/%d"
                      % (self._stamp(), sym, total, x, w))
        self.started = True
        del self.marks[:-MAX_MARKS]
        self.area.queue_draw()

    def _resolve_present(self):
        pf, self.pending_frame = self.pending_frame, None
        if not pf:
            return False
        counter, st = pf
        fc = self.get_frame_clock()
        t = fc.get_timings(counter) if fc is not None else None
        if t is not None and t.get_complete():
            pres = t.get_presentation_time()          # microseconds, or 0
            # ☠️ Is this the compositor's feedback or the frame clock's own
            # guess? GDK exposes the prediction separately, so log both: if they
            # are equal every time, the "measurement" is a model and must not be
            # quoted as one.
            pred = t.get_predicted_presentation_time()
            st["pres_us"], st["pred_us"] = pres, pred
            if pres:
                self.n_shown += 1
                st["drw_prs"] = pres / 1000.0 - st["t_drw"]
            else:
                st["drw_prs"] = None                  # compositor reports none
            st["refresh"] = t.get_refresh_interval() / 1000.0
        else:
            st["drw_prs"] = None
        for k in ("cont_raw", "evt_lat", "raw_ges", "ges_drw", "drw_prs"):
            if st.get(k) is not None:
                self.stage_counts[k] = self.stage_counts.get(k, 0) + 1
        self.stage_hist.append(dict(st))
        del self.stage_hist[:-60]          # keep the last 60
        self._log("%s  STAGES  cont->raw %s  evt->raw %s  raw->ges %s  ges->draw %s  "
                  "draw->present %s  (refresh %s)"
                  % (self._stamp(), _ms(st.get("cont_raw")), _ms(st.get("evt_lat")),
                     _ms(st.get("raw_ges")),
                     _ms(st.get("ges_drw")), _ms(st.get("drw_prs")),
                     _ms(st.get("refresh")))
                  + ("  pres=%d pred=%d delta=%.1f ms"
                     % (st.get("pres_us", 0), st.get("pred_us", 0),
                        (st.get("pres_us", 0) - st.get("pred_us", 0)) / 1000.0)))
        # Deliberately NO queue_draw() here - see the comment where this is
        # armed. The log is the measurement; the screen is a convenience.
        return False

    def _unflash(self):
        self.area.queue_draw()
        return False

    def _raw_event(self, _c, event):
        # ☠️ In the CAPTURE phase the signal hands over None here; the event has
        # to be fetched from the controller instead. Measured 2026-09-06: every
        # press raised AttributeError inside the handler, which GTK swallows -
        # the app kept running, the counter stayed 0, and the log showed nothing
        # but n/a. A handler that throws looks exactly like one that is not
        # being called.
        if event is None:
            event = _c.get_current_event()
        if event is None:
            return False
        et = event.get_event_type()
        # ☠️ TOUCH_END is tracked so a swallowed TOUCH_BEGIN can be attributed.
        # Measured 2026-09-06: 40 of 1030 touch-begins produced no tap, every
        # one of them next to a BREAK - the kernel and the compositor delivered
        # them and GTK's gesture recogniser dropped them. GestureClick handles
        # ONE sequence at a time, so a second finger landing before the first
        # lifts is the leading suspect, and only the overlap tells them apart.
        if et == Gdk.EventType.TOUCH_END:
            self.n_down = max(0, getattr(self, "n_down", 0) - 1)
            return False
        if et == Gdk.EventType.TOUCH_CANCEL:
            self.n_cancel = getattr(self, "n_cancel", 0) + 1
            self._log("%s  RAW touch-cancel #%d  (fingers down %d)"
                      % (self._stamp(), self.n_cancel, getattr(self, "n_down", 0)))
            self.n_down = max(0, getattr(self, "n_down", 0) - 1)
            return False
        if et in (Gdk.EventType.TOUCH_BEGIN, Gdk.EventType.BUTTON_PRESS):
            now = self._mono()
            evt = float(event.get_time())          # milliseconds, compositor clock
            # ☠️ On wlroots the GdkEvent time is CLOCK_MONOTONIC milliseconds -
            # the same clock as _mono() - so the difference IS the transport
            # latency and no offset is needed. But that is an assumption about
            # the compositor, so TEST it instead of trusting it: a difference
            # outside 0..2000 ms means the clocks do not share an origin, and
            # the stage is then reported as unusable rather than as a number.
            # Calibrating an offset from the first event would have made the
            # test circular - the first sample would read 0 ms by construction.
            d = now - evt
            usable = 0.0 <= d <= 2000.0
            if self.evt_offset_ok is None:
                self.evt_offset_ok = usable
                self._log("%s  event clock: now-evt = %.1f ms  usable=%s"
                          % (self._stamp(), d, usable))
            lat = d if usable else None
            if et == Gdk.EventType.TOUCH_BEGIN:
                self.n_raw += 1
                self.n_down = getattr(self, "n_down", 0) + 1
            cont = None
            if self.contact_mono is not None:
                cont = now - self.contact_mono
                if not 0.0 <= cont <= 2000.0:      # not this tap's contact
                    cont = None
                self.contact_mono = None
            self.stage = {"t_raw": now, "evt_lat": lat, "cont_raw": cont,
                          "touch": et == Gdk.EventType.TOUCH_BEGIN}
            ok, ex, ey = event.get_position()
            self.touch_seen = True
            self._log("%s  RAW %s #%d  evt->raw %s  at %s  fingers-down %d"
                      % (self._stamp(), et.value_nick, self.n_raw,
                         ("%.1f ms" % lat) if lat is not None else "n/a",
                         ("%.0f,%.0f" % (ex, ey)) if ok else "?",
                         getattr(self, "n_down", 0)))
            if ok:
                self.stage["t_ges"] = self.stage["t_raw"]
                self.stage["raw_ges"] = 0.0
                self._handle_tap(ex, ey, getattr(self, "n_down", 1))
        return False

    # ── drawing ────────────────────────────────────────────────────────────
    def _draw(self, _area, cr, w, h, *_):
        # ☠️ Log WHEN a frame is actually painted, not only when one is asked
        # for. Measured 2026-09-06: every tap was delivered and logged, and the
        # operator still saw nothing until the NEXT tap - queue_draw() had run,
        # so the loss was in presentation, not in input. Without this line the
        # log cannot tell those two apart, and the operator's eye gets blamed.
        self.n_draw += 1
        self._log("%s  DRAW #%d  marks=%d" % (self._stamp(), self.n_draw,
                                              len(self.marks)))
        if "t_ges" in self.stage and "t_drw" not in self.stage:
            self.stage["t_drw"] = self._mono()
            self.stage["ges_drw"] = self.stage["t_drw"] - self.stage["t_ges"]
            fc = self.get_frame_clock()
            if fc is not None:
                # Resolve THIS frame's presentation time later: the timings
                # are not complete until the compositor reports the frame back.
                # ☠️ THE RESOLVE MUST NOT REPAINT. An earlier version called
                # queue_draw() here so the number could be shown at once, and
                # the operator reported the display had become slower than the
                # version without any of this - the instrument was degrading
                # the thing it measures, one forced frame per tap. The numbers
                # taken that way (118 / 80 / 73 ms) are contaminated and were
                # withdrawn. Now the resolve only logs and stores; the blocks
                # update at the next natural paint, which is the next tap.
                self.pending_frame = (fc.get_frame_counter(), self.stage)
                GLib.timeout_add(400, self._resolve_present)
        mark_y, half_y = h * MARK_TOP, h * HALVES_TOP

        cr.set_source_rgb(0.06, 0.06, 0.08)   # record area
        cr.rectangle(0, 0, w, mark_y)
        cr.fill()
        if time.time() < self.mark_flash_until:
            cr.set_source_rgb(0.95, 0.85, 0.30)   # MARK, just pressed
        else:
            cr.set_source_rgb(0.40, 0.27, 0.27)
        cr.rectangle(0, mark_y, w, half_y - mark_y)
        cr.fill()
        flash = time.time() < self.half_flash_until
        if flash and self.half_flash_side == ".":
            cr.set_source_rgb(0.35, 0.85, 0.55)   # left half, just pressed
        else:
            cr.set_source_rgb(0.13, 0.27, 0.20)
        cr.rectangle(0, half_y, w / 2, h - half_y)
        cr.fill()
        if flash and self.half_flash_side == "o":
            cr.set_source_rgb(0.40, 0.70, 0.95)   # right half, just pressed
        else:
            cr.set_source_rgb(0.13, 0.20, 0.27)
        cr.rectangle(w / 2, half_y, w - w / 2, h - half_y)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)            # the single vertical divider
        cr.rectangle(w / 2 - 1, half_y, 2, h - half_y)
        cr.fill()

        # ☠️ THE WARNING BANDS. A frame that only exists as a threshold in the
        # code cannot be avoided by a hand: on 2026-09-08 the operator's finger
        # walked from x=29 to x=7 over six seconds and off the digitizer, with
        # nothing on screen marking where the sensor ends. These are the same
        # numbers the detector uses, drawn - so the beep and the picture can
        # never disagree, which they would the moment either had its own copy.
        cr.set_source_rgba(0.95, 0.65, 0.15, 0.30)
        th = h - half_y
        cr.rectangle(0, half_y, EDGE_MARGIN, th)                    # left
        cr.rectangle(w - EDGE_MARGIN, half_y, EDGE_MARGIN, th)      # right
        cr.rectangle(0, h - EDGE_MARGIN_BOTTOM, w, EDGE_MARGIN_BOTTOM)   # bottom
        # ☠️ The screen's own top edge was ALREADY a detection margin and had
        # never been drawn, because the bands were painted only inside the
        # halves. An unseen guard is exactly the failure being fixed here, so
        # it is drawn now even though the code for it is unchanged. It goes
        # under the instruction text, which is painted afterwards.
        cr.rectangle(0, 0, w, EDGE_MARGIN)                          # top of screen
        cr.fill()
        # Both sides of the split, and both sides of the field's top edge,
        # drawn as bands centred on the line they guard.
        cr.set_source_rgba(0.95, 0.45, 0.45, 0.30)
        cr.rectangle(w / 2 - DIVIDER_MARGIN, half_y, 2 * DIVIDER_MARGIN, th)
        cr.rectangle(0, half_y - HALVES_TOP_MARGIN, w, 2 * HALVES_TOP_MARGIN)
        cr.fill()

        # Where the finger actually landed, for the whole flash. A tap that
        # registered on the wrong side of the divider is then visible as such
        # instead of being read as a lost tap.
        if flash and self.tap_xy:
            cr.set_source_rgb(1, 1, 1)
            cr.arc(self.tap_xy[0], self.tap_xy[1], 14, 0, 6.2832)
            cr.fill()

        cr.select_font_face("monospace")
        cr.set_source_rgb(1, 1, 1)
        cr.set_font_size((h - half_y) * 0.45)
        cr.move_to(w / 4 - 8, half_y + (h - half_y) * 0.65)
        cr.show_text(".")
        cr.move_to(3 * w / 4 - 10, half_y + (h - half_y) * 0.65)
        cr.show_text("o")
        cr.set_font_size((half_y - mark_y) * 0.45)
        if time.time() < self.mark_flash_until:
            cr.set_source_rgb(0.1, 0.1, 0.1)
        label = "MARK  %d" % self.n_mark if self.n_mark else "MARK"
        cr.move_to(w / 2 - len(label) * (half_y - mark_y) * 0.13,
                   mark_y + (half_y - mark_y) * 0.66)
        cr.show_text(label)

        if not self.started:
            cr.set_source_rgb(0.6, 0.68, 0.74)
            cr.set_font_size(11)
            for i, line in enumerate(INSTRUCTIONS):
                cr.move_to(10, 20 + i * 15)
                cr.show_text(line)
            return

        # ★ The newest symbol, big, in its own place. One tap now changes
        # something the size of a thumb instead of one 16 px glyph buried in a
        # block of 167 identical ones.
        if self.marks:
            cr.set_source_rgb(0.95, 0.85, 0.30)
            cr.set_font_size(mark_y * 0.30)
            cr.move_to(w - mark_y * 0.30, mark_y - 12)
            cr.show_text(self.marks[-1])

        # A tick that changes colour on EVERY paint. If the screen stops
        # updating, this stops changing - so "did a frame reach the panel"
        # becomes visible without tapping anything. It does not FORCE a paint,
        # so it cannot alter the scanout behaviour under test.
        cr.set_source_rgb(*[(0.9, 0.2, 0.2), (0.2, 0.9, 0.2), (0.2, 0.4, 0.95),
                            (0.9, 0.9, 0.2)][self.n_draw % 4])
        cr.rectangle(w - 26, 8, 18, 18)
        cr.fill()

        cr.set_source_rgb(0.55, 0.9, 0.85)
        cr.set_font_size(17)
        cr.move_to(10, 26)
        # raw vs gest is the whole diagnosis in two numbers: raw is what the
        # compositor delivered, gest is what GestureClick turned into a click.
        # A gap between them IS the lost taps, and it must stay on screen.
        cr.show_text("%d  (. %d / o %d)  raw %d  gest %d  breaks %d  marks %d"
                     % (self.n_dot + self.n_o, self.n_dot, self.n_o,
                        self.n_raw, self.n_gesture, self.breaks, self.n_mark))

        # ── the four stages, STACKED, each with its own running light ──────
        # One row per hop. Each row carries, left to right: the hop's name and
        # its last value, a sparkline of the last 12 samples, and a running
        # light that steps only when THAT hop produces a new sample. A stage
        # that stops being measured therefore freezes its own light while the
        # others keep running - which is visible at a glance and was not
        # before, when a stale stage and a fast one looked identical.
        st = self.stage_hist[-1] if self.stage_hist else {}
        refresh = st.get("refresh") or 16.7
        # ── the layers as COUNTS, and the running light as the DELTA ──────
        # Each row is a counter, and its six cells are the last six one-second
        # windows. A cell is GREEN when that layer saw the same number of
        # events in that second as the layer ABOVE it, and RED when it saw
        # fewer - that cell is then the transition that dropped them, named and
        # placed in time without reading a single number.
        #
        # ☠️ ONLY contact -> raw -> gest -> tap is one event per touch, so only
        # those rows are judged. `irq` is many events per touch and `shown` is
        # frames, not touches; both are shown as counts and never coloured red,
        # because a row that cries wolf every window teaches the operator to
        # ignore the colour - which is the failure this whole instrument
        # exists to avoid.
        # ☠️ The chain FORKS at raw: both `gest` and `tap` are downstream of
        # it, because taps come from the raw touch now and GestureClick is only
        # a control. Chaining tap after gest painted tap amber whenever GTK
        # dropped one - "more than the layer above", which is true and
        # meaningless. Each row names its own reference instead.
        REF = {"raw": "contact", "gest": "raw", "tap": "raw"}
        rows = (("irq", "irq", False),
                ("contact", "contact", True),
                ("raw", "raw", True),
                ("gest", "gest", True),
                ("tap", "tap", True),
                ("shown", "shown", False))
        counts = self._counters()
        rowh, y0 = 30, 32
        cr.set_font_size(10)
        for i, (name, key, judged) in enumerate(rows):
            ry = y0 + i * rowh
            cr.set_source_rgb(0.14, 0.14, 0.17)
            cr.rectangle(10, ry, w - 20, rowh - 4)
            cr.fill()

            chip = (0.30, 0.55, 0.75) if not judged else (0.25, 0.45, 0.35)
            cr.set_source_rgb(*chip)
            cr.rectangle(10, ry, 92, rowh - 4)
            cr.fill()
            cr.set_source_rgb(0.03, 0.03, 0.03)
            cr.set_font_size(10)
            cr.move_to(14, ry + 11)
            cr.show_text(name if judged else name + "  (not 1:1)")
            cr.set_font_size(13)
            cr.move_to(14, ry + 24)
            cr.show_text("%d" % counts.get(key, 0))

            # six cells = the last six one-second windows
            cx = 110
            cw = (w - 20 - 110) / 6.0
            above = REF.get(key) if judged else None
            for j in range(6):
                d = self.win[j] if j < len(self.win) else None
                if d is None:
                    col = (0.20, 0.20, 0.24)          # no window yet
                elif not judged:
                    col = ((0.30, 0.55, 0.75) if d.get(key)
                           else (0.20, 0.20, 0.24))
                elif above is None:
                    # `contact` has no 1:1 predecessor, but the ASYMMETRY is
                    # still readable: interrupts moved and no contact came out
                    # is the driver swallowing it. That is the rule this port
                    # already uses in fp3-touch-gaps - never a ratio, only
                    # "one moved and the other did not".
                    if d.get("irq") and not d.get(key):
                        col = (0.90, 0.25, 0.25)
                    elif d.get(key):
                        col = (0.25, 0.80, 0.40)
                    else:
                        col = (0.20, 0.20, 0.24)
                else:
                    mine, ref = d.get(key, 0), d.get(above, 0)
                    if ref == 0 and mine == 0:
                        col = (0.20, 0.20, 0.24)      # nothing happened
                    elif mine < ref:
                        col = (0.90, 0.25, 0.25)      # THIS hop dropped them
                    elif mine > ref:
                        col = (0.95, 0.80, 0.25)      # more than above: odd
                    else:
                        col = (0.25, 0.80, 0.40)
                cr.set_source_rgb(*col)
                cr.rectangle(cx + j * cw, ry + 6, cw - 3, rowh - 15)
                cr.fill()
                if d is not None and (d.get(key) or 0) and cw > 22:
                    cr.set_source_rgb(0.03, 0.03, 0.03)
                    cr.set_font_size(10)
                    cr.move_to(cx + j * cw + 4, ry + rowh - 11)
                    cr.show_text("%d" % d.get(key, 0))

        # The marks, newest last, wrapped to the width and clipped to the area.
        cr.set_source_rgb(0.93, 0.93, 0.93)
        # Adwaita Mono is the only monospace font installed here that draws a
        # DOTTED zero (verified by rendering 0/o/O in each). That matters: the
        # two-finger marker must not read as the right half's 'o'.
        cr.select_font_face("Adwaita Mono")
        size = 16
        cr.set_font_size(size)
        per_line = max(8, int((w - 20) / (size * 0.72)))
        rows = int((mark_y - 220) / (size + 4))
        text = "".join(self.marks)
        lines = [text[i:i + per_line] for i in range(0, len(text), per_line)]
        shown = lines[-rows:]
        for i, line in enumerate(shown):
            cr.move_to(10, 228 + i * (size + 4))
            if i == len(shown) - 1 and line:
                cr.set_source_rgb(0.93, 0.93, 0.93)
                cr.show_text(line[:-1])
                cr.set_source_rgb(0.95, 0.85, 0.30)   # the newest one
                cr.show_text(line[-1])
            else:
                cr.set_source_rgb(0.93, 0.93, 0.93)
                cr.show_text(line)


def main():
    app = Gtk.Application(application_id="org.fp3.taptest")
    app.connect("activate", lambda a: TapTest(a).present())
    app.run(None)


main()
