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
        raw.connect("event", self._raw_event)
        self.area.add_controller(raw)
        self.n_raw = 0

        GLib.timeout_add(3000, self._geom_once)

    # ── logging ────────────────────────────────────────────────────────────
    def _log(self, line):
        self.log.write(line + "\n")

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

    def _unflash(self):
        self.area.queue_draw()
        return False

    def _raw_event(self, _c, event):
        if event.get_event_type() == Gdk.EventType.TOUCH_BEGIN:
            self.n_raw += 1
            self._log("%s  RAW touch-begin #%d" % (self._stamp(), self.n_raw))
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
        cr.set_source_rgb(0.13, 0.27, 0.20)   # left half
        cr.rectangle(0, half_y, w / 2, h - half_y)
        cr.fill()
        cr.set_source_rgb(0.13, 0.20, 0.27)   # right half
        cr.rectangle(w / 2, half_y, w - w / 2, h - half_y)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)            # the single vertical divider
        cr.rectangle(w / 2 - 1, half_y, 2, h - half_y)
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

        cr.set_source_rgb(0.55, 0.9, 0.85)
        cr.set_font_size(17)
        cr.move_to(10, 26)
        cr.show_text("%d  (. %d / o %d)  raw %d  breaks %d  marks %d"
                     % (self.n_dot + self.n_o, self.n_dot, self.n_o,
                        self.n_raw, self.breaks, self.n_mark))

        # The marks, newest last, wrapped to the width and clipped to the area.
        cr.set_source_rgb(0.93, 0.93, 0.93)
        size = 16
        cr.set_font_size(size)
        per_line = max(8, int((w - 20) / (size * 0.72)))
        rows = int((mark_y - 40) / (size + 4))
        text = "".join(self.marks)
        lines = [text[i:i + per_line] for i in range(0, len(text), per_line)]
        for i, line in enumerate(lines[-rows:]):
            cr.move_to(10, 48 + i * (size + 4))
            cr.show_text(line)


def main():
    app = Gtk.Application(application_id="org.fp3.taptest")
    app.connect("activate", lambda a: TapTest(a).present())
    app.run(None)


main()
