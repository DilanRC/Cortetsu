"""In-realm client for the simulator's control interface; prints one JSON line.

The host runs this inside the realm sandbox instead of connecting to a socket
that realm processes could replace.
"""
from __future__ import annotations

import json
import os
import sys

from gi.repository import Gio, GLib

from .daemon import CONTROL_NAME, CONTROL_PATH

SIGNATURES = {"Apply": "(s)", "Set": "(as)", "Event": "(s)", "State": None, "Reset": None}


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in SIGNATURES:
        print(json.dumps({"error": "uso: ctl Apply|Set|Event|State|Reset [args]"}))
        return 2
    name, args = argv[0], argv[1:]
    sig = SIGNATURES[name]
    params = None if sig is None else GLib.Variant(sig, (args,) if sig == "(as)" else (args[0],))
    try:
        bus = Gio.DBusConnection.new_for_address_sync(
            os.environ["DBUS_SYSTEM_BUS_ADDRESS"],
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        reply = bus.call_sync(CONTROL_NAME, CONTROL_PATH, CONTROL_NAME, name, params,
                              GLib.VariantType("(s)"), Gio.DBusCallFlags.NONE, 15000, None)
    except (GLib.Error, IndexError, KeyError) as exc:
        if isinstance(exc, GLib.Error):
            Gio.DBusError.strip_remote_error(exc)  # strips in place; returns a bool
            message = exc.message
        else:
            message = str(exc)
        print(json.dumps({"error": message}, ensure_ascii=False))
        return 3
    print(reply.unpack()[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
