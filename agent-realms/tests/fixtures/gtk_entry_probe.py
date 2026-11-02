#!/usr/bin/env python3
"""GTK4 text entry for end-to-end input checks.

Enter writes the text to $HOME/entry-result.txt and sets the window title to
"submitted: <text>", so a client can verify click + type + Enter without OCR.
"""
import os

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk


class EntryProbe(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="org.cortetsu.AgentRealmEntryProbe")

    def do_activate(self) -> None:
        # A blinking caret would make every frame differ; visual-change checks need a still screen.
        Gtk.Settings.get_default().set_property("gtk-cursor-blink", False)
        window = Gtk.ApplicationWindow(application=self, title="entry probe: waiting")
        window.set_default_size(800, 500)
        entry = Gtk.Entry(placeholder_text="type here", hexpand=True, vexpand=True)
        entry.connect("activate", self._submitted, window)
        window.set_child(entry)
        window.present()

    def _submitted(self, entry: Gtk.Entry, window: Gtk.ApplicationWindow) -> None:
        text = entry.get_text()
        with open(os.path.join(os.environ["HOME"], "entry-result.txt"), "w") as handle:
            handle.write(text)
        window.set_title(f"submitted: {text}")


if __name__ == "__main__":
    EntryProbe().run(None)
