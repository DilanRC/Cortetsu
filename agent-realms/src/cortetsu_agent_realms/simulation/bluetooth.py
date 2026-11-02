"""Fake BlueZ: ObjectManager, adapter hci0, devices with optional Battery1."""
from __future__ import annotations

from typing import Any, Callable

from gi.repository import GLib

from .dbus import V, DBusFailure, Exported, Service, iface, method, node, prop, signal


# -- BlueZ -------------------------------------------------------------------------------------

BLUEZ = "org.bluez"
ADAPTER = "org.bluez.Adapter1"
DEVICE1 = "org.bluez.Device1"
BATTERY1 = "org.bluez.Battery1"
OM = "org.freedesktop.DBus.ObjectManager"
HCI = "/org/bluez/hci0"
OM_NODE = node(iface(OM, method("GetManagedObjects", outs="a{oa{sa{sv}}}") +
                     signal("InterfacesAdded", "oa{sa{sv}}") + signal("InterfacesRemoved", "oas")))
ADAPTER_NODE = node(iface(ADAPTER, "".join([
    method("StartDiscovery"), method("StopDiscovery"), method("RemoveDevice", "o"),
    method("SetDiscoveryFilter", "a{sv}"), method("GetDiscoveryFilters", outs="as")]
    + [prop(n, t) for n, t in (("Address", "s"), ("AddressType", "s"), ("Name", "s"), ("Class", "u"),
                              ("Discovering", "b"), ("UUIDs", "as"), ("Modalias", "s"), ("PowerState", "s"))]
    + [prop(n, t, "readwrite") for n, t in (("Alias", "s"), ("Powered", "b"), ("Discoverable", "b"),
                                           ("Pairable", "b"), ("PairableTimeout", "u"),
                                           ("DiscoverableTimeout", "u"))])))
_DEVICE_IFACE = iface(DEVICE1, "".join(
    [method(m) for m in ("Connect", "Disconnect", "Pair", "CancelPairing")]
    + [prop(n, t) for n, t in (("Address", "s"), ("AddressType", "s"), ("Name", "s"), ("Icon", "s"),
                              ("Class", "u"), ("Paired", "b"), ("Bonded", "b"), ("Connected", "b"),
                              ("UUIDs", "as"), ("Adapter", "o"), ("LegacyPairing", "b"), ("RSSI", "n"),
                              ("ServicesResolved", "b"))]
    + [prop(n, t, "readwrite") for n, t in (("Alias", "s"), ("Trusted", "b"), ("Blocked", "b"),
                                           ("WakeAllowed", "b"))]))
DEVICE_NODE_BT = node(_DEVICE_IFACE)
DEVICE_BATTERY_NODE = node(_DEVICE_IFACE + iface(BATTERY1, prop("Percentage", "y") + prop("Source", "s")))


class BlueZ(Service):
    bus_names = (BLUEZ,)

    def __init__(self, *args: Any) -> None:
        super().__init__(*args)
        self.discovery_timer = 0

    @property
    def available(self) -> bool:
        return self.state()["bluetooth"]["available"]

    def bt(self) -> dict[str, Any]:
        return self.state()["bluetooth"]

    def dev_path(self, device: dict[str, Any]) -> str:
        return f"{HCI}/dev_{device['address'].replace(':', '_')}"

    def _guard(self) -> None:
        if self.bt()["fail_operations"]:
            raise DBusFailure("org.bluez.Error.Failed", "operación rechazada por el escenario")

    def _adapter_props(self, _iface: str) -> dict[str, V]:
        a = self.bt()["adapter"]
        return {"Address": V("s", "02:B7:00:00:00:01"), "AddressType": V("s", "public"),
                "Name": V("s", "realm"), "Alias": V("s", a["alias"]), "Class": V("u", 0x7C010C),
                "Powered": V("b", a["powered"]), "PowerState": V("s", "on" if a["powered"] else "off"),
                "Discoverable": V("b", a["discoverable"]), "DiscoverableTimeout": V("u", 180),
                "Pairable": V("b", a["pairable"]), "PairableTimeout": V("u", 0),
                "Discovering": V("b", a["discovering"]), "UUIDs": V("as", []), "Modalias": V("s", "usb:v1D6Bp0246d0548")}

    def _device_props(self, d: dict[str, Any], iface_name: str) -> dict[str, V]:
        if iface_name == BATTERY1:
            return {"Percentage": V("y", d["battery"] or 0), "Source": V("s", "Agent Realms")}
        return {"Address": V("s", d["address"]), "AddressType": V("s", "public"), "Name": V("s", d["name"]),
                "Alias": V("s", d["name"]), "Icon": V("s", d["icon"]), "Class": V("u", 0),
                "Paired": V("b", d["paired"]), "Bonded": V("b", d["paired"]), "Trusted": V("b", d["trusted"]),
                "Blocked": V("b", False), "WakeAllowed": V("b", False), "Connected": V("b", d["connected"]),
                "UUIDs": V("as", []), "Adapter": V("o", HCI), "LegacyPairing": V("b", False),
                "RSSI": V("n", -48), "ServicesResolved": V("b", d["connected"])}

    def _set_adapter(self, key: str) -> Callable[[Any], str | None]:
        def setter(value: Any) -> str | None:
            if self.bt()["fail_operations"]:
                return "rechazado"
            self.bt()["adapter"][key] = value
            if key == "powered" and not value:
                for d in self.bt()["devices"]:
                    d["connected"] = False
            self.changed()
            return None
        return setter

    def _discovery(self, on: bool) -> None:
        self._guard()
        adapter = self.bt()["adapter"]
        if not adapter["powered"]:
            raise DBusFailure("org.bluez.Error.NotReady", "Resource Not Ready")
        adapter["discovering"] = on
        self.changed()
        if on:
            def reveal() -> bool:
                known = {d["address"] for d in self.bt()["devices"]}
                self.bt()["devices"] += [dict(d) for d in self.bt()["nearby"] if d["address"] not in known]
                self.changed()
                return False
            GLib.timeout_add(500, reveal)

    def _device_methods(self, device: dict[str, Any]) -> dict[str, Callable[..., Any]]:
        def connect() -> None:
            self._guard()
            if not self.bt()["adapter"]["powered"]:
                raise DBusFailure("org.bluez.Error.NotReady", "Resource Not Ready")
            device["connected"] = True
            self.changed()

        def disconnect() -> None:
            device["connected"] = False
            self.changed()

        def pair() -> None:
            self._guard()
            if device["paired"]:
                raise DBusFailure("org.bluez.Error.AlreadyExists", "Already Exists")
            device["paired"] = device["trusted"] = True
            self.changed()
        return {f"{DEVICE1}.Connect": connect, f"{DEVICE1}.Disconnect": disconnect,
                f"{DEVICE1}.Pair": pair, f"{DEVICE1}.CancelPairing": lambda: None}

    def _remove_device(self, path: str) -> None:
        self._guard()
        self.bt()["devices"] = [d for d in self.bt()["devices"] if self.dev_path(d) != path]
        self.changed()

    def managed_objects(self) -> V:
        result = {path: obj.all_properties() for path, obj in self.objects.items() if path != "/"}
        return V("(a{oa{sa{sv}}})", (result,))

    def build(self):
        bt = self.bt()
        objects: dict[str, Any] = {"/": (OM_NODE, lambda _i: {}, {f"{OM}.GetManagedObjects": self.managed_objects}, {})}
        if not bt["adapter"]["present"]:
            return objects
        objects[HCI] = (ADAPTER_NODE, self._adapter_props, {
            f"{ADAPTER}.StartDiscovery": lambda: self._discovery(True),
            f"{ADAPTER}.StopDiscovery": lambda: self._discovery(False),
            f"{ADAPTER}.RemoveDevice": self._remove_device,
            f"{ADAPTER}.SetDiscoveryFilter": lambda _f: None,
            f"{ADAPTER}.GetDiscoveryFilters": lambda: V("(as)", ([],))},
            {f"{ADAPTER}.{p}": self._set_adapter(k) for p, k in (
                ("Powered", "powered"), ("Discoverable", "discoverable"), ("Pairable", "pairable"),
                ("Alias", "alias"))} | {f"{ADAPTER}.PairableTimeout": lambda _v: None,
                                        f"{ADAPTER}.DiscoverableTimeout": lambda _v: None})
        for d in bt["devices"]:
            info = DEVICE_BATTERY_NODE if d["battery"] is not None else DEVICE_NODE_BT
            objects[self.dev_path(d)] = (info, lambda i, d=d: self._device_props(d, i), self._device_methods(d), {
                f"{DEVICE1}.Trusted": lambda v, d=d: d.__setitem__("trusted", bool(v)) or self.changed(),
                f"{DEVICE1}.Alias": lambda _v: None, f"{DEVICE1}.Blocked": lambda _v: None,
                f"{DEVICE1}.WakeAllowed": lambda _v: None})
        return objects

    def on_added(self, path: str, obj: Exported) -> None:
        if path != "/":
            self.emit("/", OM, "InterfacesAdded", "oa{sa{sv}}", path, obj.all_properties())

    def on_removed(self, path: str, obj: Exported) -> None:
        if path != "/":
            self.emit("/", OM, "InterfacesRemoved", "oas", path, obj.interfaces)
