#!/usr/bin/env python3
"""Small GTK surface for visually checking realm virtual pointer input."""

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk


class InputProbe(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="org.cortetsu.AgentRealmInputProbe")
        self.status: Gtk.Label

    def do_activate(self) -> None:
        window = Gtk.ApplicationWindow(application=self)
        window.set_title("Agent Realm input probe")
        window.set_default_size(900, 720)

        layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        layout.set_margin_top(12)
        layout.set_margin_bottom(12)
        layout.set_margin_start(12)
        layout.set_margin_end(12)

        self.status = Gtk.Label(label="READY · click, drag, and scroll this window")
        self.status.set_xalign(0)
        layout.append(self.status)

        button = Gtk.Button(label="CLICK BUTTON")
        button.connect("clicked", self._button_clicked)
        layout.append(button)

        canvas = Gtk.DrawingArea()
        canvas.set_content_width(840)
        canvas.set_content_height(180)
        canvas.set_draw_func(self._draw_canvas)
        click = Gtk.GestureClick()
        click.connect("pressed", self._clicked)
        canvas.add_controller(click)
        drag = Gtk.GestureDrag()
        drag.connect("drag-update", self._drag_update)
        canvas.add_controller(drag)
        layout.append(canvas)

        rows = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        rows.set_margin_top(8)
        for index in range(100):
            label = Gtk.Label(label=f"SCROLL ROW {index:03d}")
            label.set_xalign(0)
            rows.append(label)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_child(rows)
        scroll.get_vadjustment().connect("value-changed", self._scrolled)
        wheel = Gtk.EventControllerScroll.new(Gtk.EventControllerScrollFlags.BOTH_AXES)
        wheel.connect("scroll", self._wheel_event)
        scroll.add_controller(wheel)
        layout.append(scroll)

        window.set_child(layout)
        window.present()

    @staticmethod
    def _draw_canvas(_canvas, context, width: int, height: int, _data=None) -> None:
        context.set_source_rgb(0.08, 0.13, 0.2)
        context.rectangle(0, 0, width, height)
        context.fill()

    def _clicked(self, _gesture, _count: int, x: float, y: float) -> None:
        self.status.set_text(f"CLICK · x={x:.0f} y={y:.0f}")

    def _button_clicked(self, _button) -> None:
        self.status.set_text("BUTTON CLICKED")

    def _drag_update(self, _gesture, dx: float, dy: float) -> None:
        if abs(dx) + abs(dy) > 4:
            self.status.set_text(f"DRAG UPDATE · dx={dx:.0f} dy={dy:.0f}")

    def _scrolled(self, adjustment) -> None:
        self.status.set_text(f"SCROLL · offset={adjustment.get_value():.0f}")

    def _wheel_event(self, _controller, dx: float, dy: float) -> bool:
        self.status.set_text(f"WHEEL · dx={dx:.1f} dy={dy:.1f}")
        return False


InputProbe().run(None)
