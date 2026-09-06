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
"""
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib
import time

LOG = "/home/fp3/taptest.log"
MARK_TOP, HALVES_TOP = 4.0 / 8.0, 5.0 / 8.0
MAX_MARKS = 600
INSTRUCTIONS = [
    "Tap the two lower halves ALTERNATELY:",
    "   .   o   .   o   .   o",
    "",
    "The app logs a BREAK by itself whenever",
    "the alternation fails - you do not have",
    "to spot it.",
    "",
    "Press MARK when you feel a tap was lost.",
]


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
        self.breaks = self.n_mark = self.run_len = 0
        self.last = None
        self.started = False
        self.n_draw = 0
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
        self.pending_frame = None      # (frame_counter, stage dict)
        self.evt_offset = None         # GdkEvent clock -> CLOCK_MONOTONIC
        self.evt_offset_ok = None
        self.log = open(LOG, "a", buffering=1)
        self._log("== taptest start %s" % time.strftime("%F %H:%M:%S"))

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
        t = self._mono()
        # ☠️ Start a new record unless _raw_event just opened one for THIS tap.
        # Without this the dict kept the previous tap's t_drw, the resolve was
        # never re-armed, and a whole run produced exactly one STAGES line.
        if "t_ges" in self.stage or "t_drw" in self.stage:
            self.stage = {}
        self.stage["t_ges"] = t
        self.stage["raw_ges"] = t - self.stage["t_raw"] if "t_raw" in self.stage else None
        w, h = self.area.get_width(), self.area.get_height()
        if not h:
            return
        if y < h * MARK_TOP:
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
                self.marks.append("!")
                self._log("%s  BREAK  %s repeated, run=%d  (#%d)  x=%.0f/%d"
                          % (self._stamp(), sym, self.run_len + 1, total, x, w))
            else:
                self.run_len = 0
            self.last = sym
            self.marks.append(sym)
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
            if pres:
                st["drw_prs"] = pres / 1000.0 - st["t_drw"]
            else:
                st["drw_prs"] = None                  # compositor reports none
            st["refresh"] = t.get_refresh_interval() / 1000.0
        else:
            st["drw_prs"] = None
        self.stage_hist.append(dict(st))
        del self.stage_hist[:-60]          # keep the last 60
        self._log("%s  STAGES  evt->raw %s  raw->ges %s  ges->draw %s  "
                  "draw->present %s  (refresh %s)"
                  % (self._stamp(), _ms(st.get("evt_lat")), _ms(st.get("raw_ges")),
                     _ms(st.get("ges_drw")), _ms(st.get("drw_prs")),
                     _ms(st.get("refresh"))))
        self.area.queue_draw()
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
            self.stage = {"t_raw": now, "evt_lat": lat, "touch":
                          et == Gdk.EventType.TOUCH_BEGIN}
            self._log("%s  RAW %s #%d  evt->raw %s"
                      % (self._stamp(), et.value_nick, self.n_raw,
                         ("%.1f ms" % lat) if lat is not None else "n/a"))
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
                # Resolve THIS frame's presentation time later: the timings are
                # not complete until the compositor reports the frame back.
                # ☠️ Reading timings does not schedule a frame; the single
                # 400 ms timeout below repaints once per tap so the number can
                # be shown, and that repaint is itself a perturbation - it is
                # why the resolve is one-shot and not a tick callback.
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
            cr.set_font_size(13)
            for i, line in enumerate(INSTRUCTIONS):
                cr.move_to(10, 24 + i * 19)
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
        cr.show_text("%d  (. %d / o %d)  raw %d  breaks %d  marks %d"
                     % (self.n_dot + self.n_o, self.n_dot, self.n_o,
                        self.n_raw, self.breaks, self.n_mark))

        # ── the four stages of the last tap, at FIXED coordinates ──────────
        # One block per hop, coloured by its own threshold, so a slow hop is a
        # colour and not a number to read. Grey means the hop could not be
        # measured - never the same colour as "fast", because an unmeasured
        # stage read as green is exactly how this instrument would lie.
        st = self.stage_hist[-1] if self.stage_hist else {}
        refresh = st.get("refresh") or 16.7
        stages = (("evt->raw", st.get("evt_lat"), 12.0, 40.0),
                  ("raw->ges", st.get("raw_ges"), 5.0, 25.0),
                  ("ges->draw", st.get("ges_drw"), 8.0, 30.0),
                  ("draw->shown", st.get("drw_prs"), refresh * 1.5,
                   refresh * 4.0))
        bw, bh, y0 = (w - 20) / 4.0, 34, 34
        cr.set_font_size(11)
        for i, (name, v, warn, bad) in enumerate(stages):
            x0 = 10 + i * bw
            cr.set_source_rgb(*_stage_colour(v, warn, bad))
            cr.rectangle(x0, y0, bw - 3, bh)
            cr.fill()
            cr.set_source_rgb(0.05, 0.05, 0.05)
            cr.move_to(x0 + 4, y0 + 13)
            cr.show_text(name)
            cr.move_to(x0 + 4, y0 + 27)
            cr.show_text("--" if v is None else "%.0f ms" % v)

        # The last 12 draw->shown samples, so a single outlier cannot be read
        # as a result. Bar height is capped at 200 ms; the cap is drawn as a
        # line so a clipped bar is visibly clipped and not silently flattened.
        hist = [d.get("drw_prs") for d in self.stage_hist[-12:]]
        bx, by, bwid, bhh = 10, y0 + bh + 6, (w - 20) / 12.0, 26
        cr.set_source_rgb(0.22, 0.22, 0.25)
        cr.rectangle(bx, by, w - 20, bhh)
        cr.fill()
        for i, v in enumerate(hist):
            if v is None:
                continue
            frac = min(v, 200.0) / 200.0
            cr.set_source_rgb(*_stage_colour(v, refresh * 1.5, refresh * 4.0))
            cr.rectangle(bx + i * bwid, by + bhh * (1 - frac),
                         bwid - 2, bhh * frac)
            cr.fill()
        cr.set_source_rgb(0.5, 0.5, 0.55)
        cr.rectangle(bx, by, w - 20, 1)
        cr.fill()

        # The marks, newest last, wrapped to the width and clipped to the area.
        cr.set_source_rgb(0.93, 0.93, 0.93)
        size = 16
        cr.set_font_size(size)
        per_line = max(8, int((w - 20) / (size * 0.72)))
        rows = int((mark_y - 84) / (size + 4))
        text = "".join(self.marks)
        lines = [text[i:i + per_line] for i in range(0, len(text), per_line)]
        shown = lines[-rows:]
        for i, line in enumerate(shown):
            cr.move_to(10, 92 + i * (size + 4))
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
