#!/usr/bin/env python3
"""Temporary, controllable SNI/DBusMenu provider for manual integration tests.

Run with `python3 scripts/integration/status-notifier-fixture.py --minimal` for
one minimal SNI. Full mode enables DBusMenu by default; `--no-menu` disables it.
No service file is installed.
"""

import argparse
import os
import signal
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


SNI = "org.kde.StatusNotifierItem"
MENU = "com.canonical.dbusmenu"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"


class Item(dbus.service.Object):
    def __init__(self, bus, watcher_bus, index, args):
        self.index = index
        self.minimal = args.minimal
        self.pid = args.pid
        self.instance_id = index
        self.service = f"org.freedesktop.StatusNotifierItem-{self.pid}-{self.instance_id}"
        self.name = dbus.service.BusName(self.service, bus=bus)
        self.bus = bus
        self.watcher_bus = watcher_bus
        self.status = args.status
        self.item_id = args.id2 if index == 2 and args.id2 is not None else args.id
        self.title = f"{args.title} {index}"
        self.tooltip = args.tooltip
        self.icon = args.icon
        self.attention_icon = "" if args.minimal else args.attention_icon
        self.overlay_icon = ""
        self.only_menu = args.only_menu
        self.menu_available = not args.no_menu
        self.menu_generation = 1
        self.action_count = 0
        self.object_path = "/StatusNotifierItem"
        super().__init__(self.bus, self.object_path)
        self.menu_path = "/Menu"
        self.menu_object = None if args.minimal else Menu(self.bus, self.menu_path, self)
        self.registered = True
        self.register()

    def register(self):
        if not self.registered:
            self.instance_id += 2
            self.service = f"org.freedesktop.StatusNotifierItem-{self.pid}-{self.instance_id}"
            self.name = dbus.service.BusName(self.service, bus=self.bus)
            self.add_to_connection(self.bus, self.object_path)
            if self.menu_object:
                self.menu_object.add_to_connection(self.bus, self.menu_path)
            self.registered = True
        watcher = self.watcher_bus.get_object(WATCHER, WATCHER_PATH)
        dbus.Interface(watcher, WATCHER).RegisterStatusNotifierItem(
            self.service, reply_handler=lambda: print(f"registered {self.service}"),
            error_handler=lambda error: print(f"register failed: {error}", file=sys.stderr))

    def unregister(self):
        if not self.registered:
            return
        if self.menu_object:
            self.menu_object.remove_from_connection()
        self.remove_from_connection()
        self.bus.release_name(self.service)
        self.name = None
        self.registered = False

    def property(self, name):
        values = {
            "Category": "ApplicationStatus", "Id": self.item_id,
            "Title": self.title, "Status": self.status, "WindowId": dbus.UInt32(0),
            "IconName": self.icon, "IconPixmap": dbus.Array([], signature="(iiay)"),
            "OverlayIconName": self.overlay_icon, "OverlayIconPixmap": dbus.Array([], signature="(iiay)"),
            "AttentionIconName": self.attention_icon, "AttentionIconPixmap": dbus.Array([], signature="(iiay)"),
            "AttentionMovieName": "", "ToolTip": dbus.Struct((
                dbus.String("") if self.minimal else dbus.String(self.icon),
                dbus.Array([], signature="(iiay)"),
                dbus.String("") if self.minimal else dbus.String(self.title),
                dbus.String("") if self.minimal else dbus.String(self.tooltip))),
            "ItemIsMenu": dbus.Boolean(self.only_menu),
            "Menu": dbus.ObjectPath(self.menu_path if self.menu_available else "/"),
        }
        return values[name]

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        if interface != SNI:
            raise dbus.exceptions.DBusException("Unknown interface")
        return self.property(name)

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        names = ("Category", "Id", "Title", "Status", "WindowId", "IconName", "IconPixmap",
                 "OverlayIconName", "OverlayIconPixmap", "AttentionIconName", "AttentionIconPixmap",
                 "AttentionMovieName", "ToolTip", "ItemIsMenu", "Menu")
        return {name: self.property(name) for name in names}

    @dbus.service.method(SNI, in_signature="ii")
    def Activate(self, x, y):
        print(f"activate {self.index}")

    @dbus.service.method(SNI, in_signature="ii")
    def SecondaryActivate(self, x, y):
        print(f"secondary activate {self.index}")

    @dbus.service.method(SNI, in_signature="ii")
    def ContextMenu(self, x, y):
        print(f"context menu {self.index}")

    @dbus.service.method(SNI, in_signature="is")
    def Scroll(self, delta, orientation):
        print(f"scroll {self.index} {delta} {orientation}")

    def update(self, field, value):
        if field == "title":
            self.title = value
            signal_name = "NewTitle"
        elif field == "status":
            self.status = value
            signal_name = "NewStatus"
        elif field == "tooltip":
            self.tooltip = value
            signal_name = "NewToolTip"
        elif field == "icon":
            self.icon = value
            signal_name = "NewIcon"
        elif field == "attention-icon":
            self.attention_icon = value
            signal_name = "NewAttentionIcon"
        elif field == "overlay-icon":
            self.overlay_icon = value
            signal_name = "NewOverlayIcon"
        elif field == "menu":
            if self.menu_object is None:
                raise ValueError("menu control is unavailable in --minimal mode")
            self.menu_available = value == "on"
            self.menu_generation += 1
            signal_name = None
        elif field == "only-menu":
            self.only_menu = value == "on"
            signal_name = None
        else:
            raise ValueError(f"unknown field: {field}")
        if field == "status":
            self.NewStatus(self.status)
        elif signal_name:
            getattr(self, signal_name)()
        property_name = {"icon": "IconName", "title": "Title", "status": "Status",
                         "tooltip": "ToolTip", "menu": "Menu", "only-menu": "ItemIsMenu",
                         "attention-icon": "AttentionIconName", "overlay-icon": "OverlayIconName"}[field]
        self.PropertiesChanged(SNI, {property_name: self.property(property_name)}, [])
        if field == "menu" and self.menu_object:
            self.menu_object.LayoutUpdated(dbus.UInt32(self.menu_generation), dbus.Int32(0))

    @dbus.service.signal(SNI)
    def NewTitle(self):
        pass

    @dbus.service.signal(SNI, signature="s")
    def NewStatus(self, status):
        pass

    @dbus.service.signal(SNI)
    def NewToolTip(self):
        pass

    @dbus.service.signal(SNI)
    def NewIcon(self):
        pass

    @dbus.service.signal(SNI)
    def NewAttentionIcon(self):
        pass

    @dbus.service.signal(SNI)
    def NewOverlayIcon(self):
        pass

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class Menu(dbus.service.Object):
    def __init__(self, name, path, item):
        self.item = item
        super().__init__(name, path)

    def entry(self, node_id, depth=-1, names=()):
        label = {1: "Action", 2: "Disabled entry", 3: "Submenu", 4: "Second level", 5: "Back"}.get(node_id, "")
        props = dbus.Dictionary({"label": dbus.String(label), "enabled": dbus.Boolean(node_id != 2),
                 "visible": dbus.Boolean(True), "type": dbus.String("separator" if node_id == 6 else "standard")},
                 signature="sv")
        if node_id == 3:
            props["children-display"] = dbus.String("submenu")
        if node_id == 4:
            props["children-display"] = dbus.String("submenu")
        if names:
            props = dbus.Dictionary({key: value for key, value in props.items() if key in names},
                                    signature="sv")
        child_ids = {0: [1, 2, 3, 6, 5], 3: [4], 4: [1]}.get(node_id, [])
        if depth == 0:
            child_ids = []
        child_depth = depth - 1 if depth > 0 else depth
        variants = [dbus.Struct(self.entry(child, child_depth, names), signature="ia{sv}av", variant_level=1)
                    for child in child_ids]
        return dbus.Struct((dbus.Int32(node_id), props, dbus.Array(variants, signature="v")),
            signature="ia{sv}av")

    @dbus.service.method(MENU, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent, depth, names):
        root = self.entry(parent if parent else 0, depth, names)
        return (dbus.UInt32(self.item.menu_generation), root)

    @dbus.service.method(MENU, in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, ids, names):
        return [(node_id, self.entry(node_id, 0, names)[1]) for node_id in ids]

    @dbus.service.method(MENU, in_signature="isvu")
    def Event(self, node_id, event_id, data, timestamp):
        if node_id == 1 and event_id == "clicked":
            self.item.action_count += 1
            print(f"action {self.item.index} count={self.item.action_count}")

    @dbus.service.method(MENU, in_signature="i", out_signature="b")
    def AboutToShow(self, node_id):
        return dbus.Boolean(False)

    @dbus.service.signal(MENU, signature="ui")
    def LayoutUpdated(self, revision, parent):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", choices=("Active", "Passive", "NeedsAttention"), default="Active")
    parser.add_argument("--id", default="cortetsu-fixture")
    parser.add_argument("--id2", help="application Id for the second item")
    parser.add_argument("--title", default="Cortetsu SNI Fixture")
    parser.add_argument("--tooltip", default="Controllable SNI and DBusMenu test provider")
    parser.add_argument("--icon", default="applications-system")
    parser.add_argument("--attention-icon", default="dialog-warning")
    parser.add_argument("--only-menu", action="store_true")
    parser.add_argument("--no-menu", action="store_true")
    parser.add_argument("--pid", type=int, default=None)
    parser.add_argument("--instances", type=int, choices=(1, 2), default=1)
    parser.add_argument("--minimal", action="store_true",
                        help="one Active item with empty optional properties and no menu")
    args = parser.parse_args()
    if args.minimal:
        args.instances = 1
        args.no_menu = True
        args.icon = ""
        args.tooltip = ""
    if args.pid is None:
        args.pid = os.getpid()
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    connections = [dbus.bus.BusConnection(os.environ["DBUS_SESSION_BUS_ADDRESS"])
                   for _ in range(args.instances)]
    items = [Item(connection, bus, index, args)
             for index, connection in enumerate(connections, start=1)]

    # Control bus methods make property/menu churn and provider disappearance
    # reproducible without re-registering an item.
    control_name = dbus.service.BusName(f"org.cortetsu.SniFixture{args.pid}", bus=bus)
    control = Control(control_name, items, loop)
    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    print(f"control service org.cortetsu.SniFixture{args.pid}; Ctrl-C to unregister")
    loop.run()
    control.remove_from_connection()
    for item in items:
        item.unregister()
    for connection in connections:
        connection.close()


class Control(dbus.service.Object):
    def __init__(self, name, items, loop):
        self.items, self.loop = items, loop
        super().__init__(name, "/Fixture")

    @dbus.service.method("org.cortetsu.SniFixture", in_signature="iss")
    def Set(self, index, field, value):
        self.items[int(index) - 1].update(field, value)

    @dbus.service.method("org.cortetsu.SniFixture", in_signature="i")
    def Unregister(self, index):
        self.items[int(index) - 1].unregister()

    @dbus.service.method("org.cortetsu.SniFixture", in_signature="i")
    def Register(self, index):
        self.items[int(index) - 1].register()

    @dbus.service.method("org.cortetsu.SniFixture", in_signature="")
    def Stop(self):
        self.loop.quit()


if __name__ == "__main__":
    main()
