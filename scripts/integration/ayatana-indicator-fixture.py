#!/usr/bin/env python3
"""A real AppIndicator for tray tests: libayatana-appindicator and libdbusmenu-gtk,
the stack of nm-applet and blueman, with a three-level menu.

    python3 -I ayatana-indicator-fixture.py LOG

Rows: "Acción simple", a disabled row, a separator, "Red" > ("Wi-Fi" >
("Conectar", "Olvidar"), "VPN"), "Modo" > (radio "Modo A" on, "Modo B"),
check box "Silencio" (off), "Salir". Every activation is appended to LOG
("simple", "deep-connect", "vpn", "mode-b", "check-True"...); "ready" once
registered. SIGUSR1 renames the first row, SIGUSR2 adds a row under "Red",
SIGTERM quits like the app closing.
"""
import signal
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3 as AI, GLib, Gtk  # noqa: E402

LOG = sys.argv[1]


def note(text: str) -> None:
    with open(LOG, "a") as f:
        f.write(text + "\n")


def item(label, tag=None, sensitive=True):
    it = Gtk.MenuItem(label=label)
    it.set_sensitive(sensitive)
    if tag:
        it.connect("activate", lambda *_: note(tag))
    it.show()
    return it


def submenu(label, children):
    it = Gtk.MenuItem(label=label)
    menu = Gtk.Menu()
    for child in children:
        menu.append(child)
    menu.show()
    it.set_submenu(menu)
    it.show()
    return it, menu


root = Gtk.Menu()
first = item("Acción simple", "simple")
root.append(first)
root.append(item("Deshabilitada", "never", sensitive=False))
separator = Gtk.SeparatorMenuItem()
separator.show()
root.append(separator)
wifi, _ = submenu("Wi-Fi", [item("Conectar", "deep-connect"), item("Olvidar", "deep-forget")])
red, red_menu = submenu("Red", [wifi, item("VPN", "vpn")])
root.append(red)
mode_a = Gtk.RadioMenuItem.new_with_label([], "Modo A")
mode_b = Gtk.RadioMenuItem.new_with_label(mode_a.get_group(), "Modo B")
for widget, tag in ((mode_a, "mode-a"), (mode_b, "mode-b")):
    widget.connect("toggled", lambda w, t=tag: w.get_active() and note(t))
    widget.show()
modes, _ = submenu("Modo", [mode_a, mode_b])
root.append(modes)
check = Gtk.CheckMenuItem(label="Silencio")
check.connect("toggled", lambda w: note(f"check-{w.get_active()}"))
check.show()
root.append(check)
root.append(item("Salir", "quit"))
root.show()

indicator = AI.Indicator.new("cortetsu-qa-ayatana", "network-wireless", AI.IndicatorCategory.APPLICATION_STATUS)
indicator.set_status(AI.IndicatorStatus.ACTIVE)
indicator.set_title("Cortetsu QA")
indicator.set_menu(root)


def rename(*_):
    first.set_label("Acción renombrada")
    note("renamed")
    return True


def grow(*_):
    red_menu.append(item("Nueva fila", "grown"))
    note("grown-added")
    return True


GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, rename)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR2, grow)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda *_: (Gtk.main_quit(), False)[1])
note("ready")
Gtk.main()
