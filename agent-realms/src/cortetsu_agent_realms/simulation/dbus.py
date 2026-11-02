"""D-Bus building blocks for the fake services: exported objects and bus-name lifecycle.

An Exported object diffs its properties on each sync and emits PropertiesChanged;
a Service owns bus names and adds or removes objects as the shared state changes.
"""
from __future__ import annotations

from typing import Any, Callable

from gi.repository import Gio, GLib

V = GLib.Variant
PROPS = "org.freedesktop.DBus.Properties"


class Exported:
    """One object path with one or more interfaces, registered on a connection."""

    def __init__(self, bus: Gio.DBusConnection, node: Gio.DBusNodeInfo, path: str,
                 props: Callable[[str], dict[str, V]], *,
                 methods: dict[str, Callable[..., Any]] | None = None,
                 setters: dict[str, Callable[[Any], str | None]] | None = None):
        self.bus, self.path, self.props = bus, path, props
        self.methods, self.setters = methods or {}, setters or {}
        self.ids = [bus.register_object(path, iface, self._call, self._get, self._set)
                    for iface in node.interfaces]
        self.interfaces = [iface.name for iface in node.interfaces]
        self.last = {name: self._snapshot(name) for name in self.interfaces}

    def _snapshot(self, iface: str) -> dict[str, str]:
        return {key: value.print_(True) for key, value in self.props(iface).items()}

    def _call(self, _bus, _sender, _path, iface, method, params, invocation) -> None:
        handler = self.methods.get(f"{iface}.{method}")
        if handler is None:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)
            return
        try:
            result = handler(*params.unpack())
        except DBusFailure as exc:
            invocation.return_dbus_error(exc.name, exc.message)
            return
        invocation.return_value(result)

    def _get(self, _bus, _sender, _path, iface, name):
        return self.props(iface).get(name)

    def _set(self, _bus, _sender, _path, iface, name, value) -> bool:
        setter = self.setters.get(f"{iface}.{name}")
        # A falsy return makes GDBus answer the Set call with an error.
        return setter is not None and setter(value.unpack()) is None

    def sync(self) -> None:
        for iface in self.interfaces:
            values = self.props(iface)
            current = {key: value.print_(True) for key, value in values.items()}
            changed = {k: values[k] for k, v in current.items() if self.last[iface].get(k) != v}
            if changed:
                self.bus.emit_signal(None, self.path, PROPS, "PropertiesChanged",
                                     V("(sa{sv}as)", (iface, changed, [])))
            self.last[iface] = current

    def all_properties(self) -> dict[str, dict[str, V]]:
        return {iface: self.props(iface) for iface in self.interfaces}

    def unregister(self) -> None:
        for reg in self.ids:
            self.bus.unregister_object(reg)
        self.ids = []


class DBusFailure(Exception):
    def __init__(self, name: str, message: str):
        super().__init__(message)
        self.name, self.message = name, message


def node(xml: str) -> Gio.DBusNodeInfo:
    return Gio.DBusNodeInfo.new_for_xml(f"<node>{xml}</node>")


def iface(name: str, body: str) -> str:
    return f'<interface name="{name}">{body}</interface>'


def prop(name: str, sig: str, access: str = "read") -> str:
    return f'<property name="{name}" type="{sig}" access="{access}"/>'


def method(name: str, ins: str = "", outs: str = "") -> str:
    args = "".join(f'<arg direction="in" type="{t}"/>' for t in _split(ins))
    args += "".join(f'<arg direction="out" type="{t}"/>' for t in _split(outs))
    return f'<method name="{name}">{args}</method>'


def signal(name: str, sig: str = "") -> str:
    return f'<signal name="{name}">' + "".join(f'<arg type="{t}"/>' for t in _split(sig)) + "</signal>"


def _split(signature: str) -> list[str]:
    """Split a D-Bus signature into complete types."""
    out, i = [], 0
    while i < len(signature):
        j, depth = i, 0
        while True:
            c = signature[j]
            if c in "({":
                depth += 1
            elif c in ")}":
                depth -= 1
            j += 1
            if depth == 0 and c != "a":
                break
        out.append(signature[i:j])
        i = j
    return out


class Service:
    """A bus name plus its objects; appears and disappears with `state[...]["available"]`."""

    bus_names: tuple[str, ...] = ()

    def __init__(self, bus: Gio.DBusConnection, state: Callable[[], dict[str, Any]],
                 changed: Callable[[], None]):
        self.bus, self.state, self.changed = bus, state, changed
        self.objects: dict[str, Exported] = {}
        self.owner_ids: list[int] = []

    @property
    def available(self) -> bool:
        raise NotImplementedError

    def build(self) -> dict[str, tuple[Gio.DBusNodeInfo, Callable[[str], dict[str, V]], dict, dict]]:
        """path -> (node info, props(iface), methods, setters) for the current state."""
        raise NotImplementedError

    def on_added(self, path: str, obj: Exported) -> None:
        return

    def on_removed(self, path: str, obj: Exported) -> None:
        return

    def sync(self) -> None:
        if not self.available:
            self.stop()
            return
        wanted = self.build()
        for path in [p for p in self.objects if p not in wanted]:
            obj = self.objects.pop(path)
            self.on_removed(path, obj)
            obj.unregister()
        for path, (info, props, methods, setters) in wanted.items():
            obj = self.objects.get(path)
            if obj is not None and obj.interfaces != [i.name for i in info.interfaces]:
                # Interfaces changed (e.g. a device gained Battery1): republish like the real daemon.
                self.on_removed(path, self.objects.pop(path))
                obj.unregister()
                obj = None
            if obj is None:
                obj = Exported(self.bus, info, path, props, methods=methods, setters=setters)
                self.objects[path] = obj
                if self.owner_ids:
                    self.on_added(path, obj)
            else:
                obj.props, obj.methods, obj.setters = props, methods, setters
                obj.sync()
        if not self.owner_ids:
            # Own names after the objects exist, so the first GetAll after NameOwnerChanged succeeds.
            self.owner_ids = [Gio.bus_own_name_on_connection(self.bus, name, Gio.BusNameOwnerFlags.NONE,
                                                             None, None) for name in self.bus_names]

    def stop(self) -> None:
        for owner in self.owner_ids:
            Gio.bus_unown_name(owner)
        self.owner_ids = []
        for obj in self.objects.values():
            obj.unregister()
        self.objects = {}

    def emit(self, path: str, interface: str, name: str, sig: str, *values: Any) -> None:
        self.bus.emit_signal(None, path, interface, name, V(f"({sig})", values) if sig else None)
