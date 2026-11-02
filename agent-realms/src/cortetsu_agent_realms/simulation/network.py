"""Fake NetworkManager: Wi-Fi and Ethernet devices, access points, connections, activation."""
from __future__ import annotations

import hashlib
from typing import Any, Callable

from gi.repository import GLib

from .dbus import V, DBusFailure, Exported, Service, iface, method, node, prop, signal


# -- NetworkManager -------------------------------------------------------------------------

NM = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
NM_DEV = NM + ".Device"
NM_WIFI = NM + ".Device.Wireless"
NM_WIRED = NM + ".Device.Wired"
NM_AP = NM + ".AccessPoint"
NM_ACTIVE = NM + ".Connection.Active"
NM_SETTINGS = NM + ".Settings"
NM_CONN = NM + ".Settings.Connection"
NM_ROOT_NODE = node(iface(NM, "".join([
    method("GetDevices", outs="ao"), method("GetAllDevices", outs="ao"),
    method("ActivateConnection", "ooo", "o"), method("AddAndActivateConnection", "a{sa{sv}}oo", "oo"),
    method("DeactivateConnection", "o"), method("CheckConnectivity", outs="u"),
    signal("DeviceAdded", "o"), signal("DeviceRemoved", "o"), signal("StateChanged", "u"),
    prop("Devices", "ao"), prop("AllDevices", "ao"), prop("ActiveConnections", "ao"),
    prop("PrimaryConnection", "o"), prop("NetworkingEnabled", "b"), prop("WirelessEnabled", "b", "readwrite"),
    prop("WirelessHardwareEnabled", "b"), prop("State", "u"), prop("Connectivity", "u"),
    prop("ConnectivityCheckAvailable", "b"), prop("ConnectivityCheckEnabled", "b", "readwrite"),
    prop("Version", "s")])))
_DEV_BODY = "".join([method("Disconnect"), signal("StateChanged", "uuu")] + [prop(n, t) for n, t in (
    ("Interface", "s"), ("HwAddress", "s"), ("DeviceType", "u"), ("State", "u"), ("StateReason", "(uu)"),
    ("ActiveConnection", "o"), ("AvailableConnections", "ao"), ("Managed", "b"), ("InterfaceFlags", "u"),
    ("Driver", "s"), ("Ip4Config", "o"), ("Real", "b"))] + [prop("Autoconnect", "b", "readwrite")])
NM_WIFI_NODE = node(iface(NM_DEV, _DEV_BODY) + iface(NM_WIFI, "".join([
    method("GetAccessPoints", outs="ao"), method("GetAllAccessPoints", outs="ao"), method("RequestScan", "a{sv}"),
    signal("AccessPointAdded", "o"), signal("AccessPointRemoved", "o"),
    prop("HwAddress", "s"), prop("Mode", "u"), prop("Bitrate", "u"), prop("AccessPoints", "ao"),
    prop("ActiveAccessPoint", "o"), prop("WirelessCapabilities", "u"), prop("LastScan", "x")])))
NM_WIRED_NODE = node(iface(NM_DEV, _DEV_BODY) + iface(NM_WIRED, "".join(
    prop(n, t) for n, t in (("HwAddress", "s"), ("PermHwAddress", "s"), ("Speed", "u"), ("Carrier", "b")))))
NM_AP_NODE = node(iface(NM_AP, "".join(prop(n, t) for n, t in (
    ("Flags", "u"), ("WpaFlags", "u"), ("RsnFlags", "u"), ("Ssid", "ay"), ("Frequency", "u"), ("HwAddress", "s"),
    ("Mode", "u"), ("MaxBitrate", "u"), ("Strength", "y"), ("LastSeen", "i")))))
NM_ACTIVE_NODE = node(iface(NM_ACTIVE, signal("StateChanged", "uu") + "".join(prop(n, t) for n, t in (
    ("Connection", "o"), ("SpecificObject", "o"), ("Id", "s"), ("Uuid", "s"), ("Type", "s"), ("Devices", "ao"),
    ("State", "u"), ("StateFlags", "u"), ("Default", "b"), ("Vpn", "b")))))
NM_SETTINGS_NODE = node(iface(NM_SETTINGS, method("ListConnections", outs="ao") + prop("Connections", "ao")))
NM_CONN_NODE = node(iface(NM_CONN, "".join([
    method("GetSettings", outs="a{sa{sv}}"), method("GetSecrets", "s", "a{sa{sv}}"), method("Update", "a{sa{sv}}"),
    method("ClearSecrets"), method("Delete"), signal("Updated"), signal("Removed"),
    prop("Unsaved", "b"), prop("Flags", "u"), prop("Filename", "s")])))
NM_STATE = {"none": 20, "portal": 60, "limited": 60, "full": 70, "unknown": 0}
NM_CONNECTIVITY = {"unknown": 0, "none": 1, "portal": 2, "limited": 3, "full": 4}
ROOT_OBJ = "/"


def _digest(seed: str) -> str:
    return hashlib.sha256(seed.encode()).hexdigest()


def _uuid(seed: str) -> str:
    h = _digest(seed)
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


class NetworkManager(Service):
    """Wi-Fi and Ethernet devices, access points, saved connections and activation."""

    bus_names = (NM,)
    WIFI = NM_PATH + "/Devices/1"
    WIRED = NM_PATH + "/Devices/2"
    SETTINGS = NM_PATH + "/Settings"

    def __init__(self, *args: Any) -> None:
        super().__init__(*args)
        self.scan_time = 1
        self.device_state: dict[str, tuple[int, int]] = {}
        self.extra_saved: list[str] = []
        self.published_state: dict[str, int | None] = {}

    @property
    def available(self) -> bool:
        return self.state()["network"]["available"]

    def net(self) -> dict[str, Any]:
        return self.state()["network"]

    def ap_path(self, index: int) -> str:
        return f"{NM_PATH}/AccessPoint/{index + 1}"

    def visible_aps(self) -> list[dict[str, Any]]:
        n = self.net()
        return n["wifi"]["access_points"] if n["wifi"]["present"] and n["wireless_enabled"] else []

    def saved_ssids(self) -> list[str]:
        """Networks that were ever connected stay saved, as in NetworkManager; Delete removes them."""
        connected = self.net()["wifi"]["connected"]
        if connected and connected not in self.extra_saved:
            self.extra_saved.append(connected)
        return list(self.extra_saved)

    def conn_path(self, ssid: str) -> str:
        return f"{self.SETTINGS}/{int(_digest(ssid)[:6], 16) % 100000 + 1}"

    def wifi_state(self) -> int:
        n = self.net()
        if not n["wifi"]["present"]:
            return 0
        override = self.device_state.get(self.WIFI)
        if override:
            return override[0]
        if not n["wireless_enabled"] or not n["wireless_hardware_enabled"]:
            return 20
        return 100 if n["wifi"]["connected"] else 30

    def wired_state(self) -> int:
        eth = self.net()["ethernet"]
        return 100 if eth["connected"] else 20 if eth["present"] else 0

    def active_paths(self) -> list[str]:
        result = []
        if self.wifi_state() == 100:
            result.append(NM_PATH + "/ActiveConnection/1")
        if self.net()["ethernet"]["present"] and self.wired_state() == 100:
            result.append(NM_PATH + "/ActiveConnection/2")
        return result

    def devices(self) -> list[str]:
        return ([self.WIFI] if self.net()["wifi"]["present"] else []) + \
            ([self.WIRED] if self.net()["ethernet"]["present"] else [])

    def _root(self, _iface: str) -> dict[str, V]:
        n = self.net()
        active = self.active_paths()
        connectivity = n["connectivity"] if active else "none"
        return {"Devices": V("ao", self.devices()), "AllDevices": V("ao", self.devices()),
                "ActiveConnections": V("ao", active), "PrimaryConnection": V("o", active[-1] if active else ROOT_OBJ),
                "NetworkingEnabled": V("b", True), "WirelessEnabled": V("b", n["wireless_enabled"]),
                "WirelessHardwareEnabled": V("b", n["wireless_hardware_enabled"]),
                "State": V("u", NM_STATE[connectivity] if active else 20),
                "Connectivity": V("u", NM_CONNECTIVITY[connectivity]),
                "ConnectivityCheckAvailable": V("b", True), "ConnectivityCheckEnabled": V("b", True),
                "Version": V("s", "1.54.0")}

    def _device(self, path: str, iface_name: str) -> dict[str, V]:
        wifi = path == self.WIFI
        state = self.wifi_state() if wifi else self.wired_state()
        reason = self.device_state.get(path, (0, 0))[1]
        active = NM_PATH + ("/ActiveConnection/1" if wifi else "/ActiveConnection/2")
        connected_ssid = self.net()["wifi"]["connected"]
        available = [self.conn_path(s) for s in self.saved_ssids()] if wifi else [self.SETTINGS + "/wired"]
        hw = "02:00:00:00:00:01" if wifi else "02:00:00:00:00:02"
        if iface_name == NM_DEV:
            return {"Interface": V("s", "wlan0" if wifi else "enp1s0"), "HwAddress": V("s", hw),
                    "DeviceType": V("u", 2 if wifi else 1), "State": V("u", state), "StateReason": V("(uu)", (state, reason)),
                    "ActiveConnection": V("o", active if state == 100 else ROOT_OBJ),
                    "AvailableConnections": V("ao", available), "Managed": V("b", True),
                    "InterfaceFlags": V("u", 0x10003 if state == 100 else 0x1), "Driver": V("s", "sim"),
                    "Ip4Config": V("o", ROOT_OBJ), "Real": V("b", True), "Autoconnect": V("b", True)}
        if iface_name == NM_WIRED:
            eth = self.net()["ethernet"]
            return {"HwAddress": V("s", hw), "PermHwAddress": V("s", hw), "Speed": V("u", eth["speed"]),
                    "Carrier": V("b", eth["connected"])}
        aps = [self.ap_path(i) for i, _ in enumerate(self.visible_aps())]
        current = next((self.ap_path(i) for i, ap in enumerate(self.visible_aps())
                        if ap["ssid"] == connected_ssid), ROOT_OBJ) if state == 100 else ROOT_OBJ
        return {"HwAddress": V("s", hw), "Mode": V("u", 2), "Bitrate": V("u", 866000 if state == 100 else 0),
                "AccessPoints": V("ao", aps), "ActiveAccessPoint": V("o", current),
                "WirelessCapabilities": V("u", 0x1FF), "LastScan": V("x", self.scan_time)}

    def _ap(self, ap: dict[str, Any]) -> dict[str, V]:
        secured = ap["secured"]
        return {"Flags": V("u", 1 if secured else 0), "WpaFlags": V("u", 0),
                "RsnFlags": V("u", 0x188 if secured else 0), "Ssid": V("ay", ap["ssid"].encode()),
                "Frequency": V("u", ap["frequency"]), "HwAddress": V("s", "02:11:22:33:44:" + _digest(ap["ssid"])[:2].upper()),
                "Mode": V("u", 2), "MaxBitrate": V("u", 866000), "Strength": V("y", ap["strength"]),
                "LastSeen": V("i", self.scan_time)}

    def _active(self, wifi: bool) -> dict[str, V]:
        ssid = self.net()["wifi"]["connected"] if wifi else "Ethernet simulada"
        conn = self.conn_path(ssid) if wifi else self.SETTINGS + "/wired"
        ap = next((self.ap_path(i) for i, a in enumerate(self.visible_aps()) if a["ssid"] == ssid), ROOT_OBJ)
        return {"Connection": V("o", conn), "SpecificObject": V("o", ap if wifi else ROOT_OBJ),
                "Id": V("s", ssid), "Uuid": V("s", _uuid(ssid)),
                "Type": V("s", "802-11-wireless" if wifi else "802-3-ethernet"),
                "Devices": V("ao", [self.WIFI if wifi else self.WIRED]), "State": V("u", 2),
                "StateFlags": V("u", 0), "Default": V("b", True), "Vpn": V("b", False)}

    def _conn_settings(self, ssid: str | None) -> V:
        if ssid is None:
            settings = {"connection": {"id": V("s", "Ethernet simulada"), "uuid": V("s", _uuid("wired")),
                                       "type": V("s", "802-3-ethernet")}}
        else:
            settings = {"connection": {"id": V("s", ssid), "uuid": V("s", _uuid(ssid)),
                                       "type": V("s", "802-11-wireless")},
                        "802-11-wireless": {"ssid": V("ay", ssid.encode()), "mode": V("s", "infrastructure")}}
        return V("(a{sa{sv}})", (settings,))

    # Methods ------------------------------------------------------------------------

    def _set_wireless(self, value: bool) -> None:
        self.net()["wireless_enabled"] = bool(value)
        self.changed()

    def _ssid_for(self, specific: str) -> str | None:
        aps = self.visible_aps()
        for i, ap in enumerate(aps):
            if self.ap_path(i) == specific:
                return ap["ssid"]
        return None

    def _activate(self, ssid: str | None) -> V:
        if ssid is None:
            raise DBusFailure(NM + ".UnknownConnection", "punto de acceso desconocido")
        wifi = self.net()["wifi"]
        self.device_state[self.WIFI] = (40, 0)  # prepare
        self.changed()
        if wifi["fail_connect"]:
            GLib.timeout_add(600, self._fail_activation)
        else:
            def finish() -> bool:
                self.device_state.pop(self.WIFI, None)
                wifi["connected"] = ssid
                self.changed()
                return False
            GLib.timeout_add(600, finish)
        return NM_PATH + "/ActiveConnection/1"

    def _fail_activation(self) -> bool:
        self.device_state[self.WIFI] = (120, 7)  # failed: no secrets
        self.changed()

        def recover() -> bool:
            self.device_state.pop(self.WIFI, None)
            self.net()["wifi"]["connected"] = None
            self.changed()
            return False
        GLib.timeout_add(800, recover)
        return False

    def _activate_connection(self, connection: str, _device: str, specific: str) -> V:
        ssid = self._ssid_for(specific) or next((s for s in self.saved_ssids() if self.conn_path(s) == connection), None)
        return V("(o)", (self._activate(ssid),))

    def _add_and_activate(self, settings: dict, _device: str, specific: str) -> V:
        ssid = self._ssid_for(specific)
        raw = settings.get("802-11-wireless", {}).get("ssid")
        if ssid is None and raw:
            ssid = bytes(raw).decode(errors="replace")
        if ssid and ssid not in self.extra_saved:
            self.extra_saved.append(ssid)
        active = self._activate(ssid)
        return V("(oo)", (self.conn_path(ssid), active))

    def _disconnect(self, path: str) -> None:
        if path == self.WIFI:
            self.net()["wifi"]["connected"] = None
        else:
            self.net()["ethernet"]["connected"] = False
        self.changed()

    def request_scan(self, *_args: Any) -> None:
        wifi = self.net()["wifi"]
        known = {ap["ssid"] for ap in wifi["access_points"]}
        wifi["access_points"] += [ap for ap in wifi["nearby"] if ap["ssid"] not in known]
        self.scan_time += 1
        self.changed()

    def build(self):
        n = self.net()
        objects: dict[str, Any] = {}
        root_methods = {
            f"{NM}.GetDevices": lambda: V("(ao)", (self.devices(),)),
            f"{NM}.GetAllDevices": lambda: V("(ao)", (self.devices(),)),
            f"{NM}.ActivateConnection": self._activate_connection,
            f"{NM}.AddAndActivateConnection": self._add_and_activate,
            f"{NM}.DeactivateConnection": lambda _p: self._disconnect(self.WIFI),
            f"{NM}.CheckConnectivity": lambda: V("(u)", (NM_CONNECTIVITY[n["connectivity"]],)),
        }
        objects[NM_PATH] = (NM_ROOT_NODE, self._root, root_methods, {
            f"{NM}.WirelessEnabled": self._set_wireless, f"{NM}.ConnectivityCheckEnabled": lambda _v: None})
        saved = self.saved_ssids()
        objects[self.SETTINGS] = (NM_SETTINGS_NODE, lambda _i: {"Connections": V("ao", [self.conn_path(s) for s in saved])},
                                  {f"{NM_SETTINGS}.ListConnections": lambda: V("(ao)", ([self.conn_path(s) for s in saved],))}, {})
        conn_props = lambda _i: {"Unsaved": V("b", False), "Flags": V("u", 0), "Filename": V("s", "")}
        for ssid in saved:
            objects[self.conn_path(ssid)] = (NM_CONN_NODE, conn_props, self._conn_methods(ssid), {})
        if n["ethernet"]["present"]:
            objects[self.SETTINGS + "/wired"] = (NM_CONN_NODE, conn_props, self._conn_methods(None), {})
        if n["wifi"]["present"]:
            objects[self.WIFI] = (NM_WIFI_NODE, lambda i: self._device(self.WIFI, i), {
                f"{NM_DEV}.Disconnect": lambda: self._disconnect(self.WIFI),
                f"{NM_WIFI}.GetAccessPoints": lambda: V("(ao)", ([self.ap_path(i) for i, _ in enumerate(self.visible_aps())],)),
                f"{NM_WIFI}.GetAllAccessPoints": lambda: V("(ao)", ([self.ap_path(i) for i, _ in enumerate(self.visible_aps())],)),
                f"{NM_WIFI}.RequestScan": self.request_scan}, {f"{NM_DEV}.Autoconnect": lambda _v: None})
            for i, ap in enumerate(self.visible_aps()):
                objects[self.ap_path(i)] = (NM_AP_NODE, lambda _i, ap=ap: self._ap(ap), {}, {})
            if self.wifi_state() == 100:
                objects[NM_PATH + "/ActiveConnection/1"] = (NM_ACTIVE_NODE, lambda _i: self._active(True), {}, {})
        if n["ethernet"]["present"]:
            objects[self.WIRED] = (NM_WIRED_NODE, lambda i: self._device(self.WIRED, i),
                                   {f"{NM_DEV}.Disconnect": lambda: self._disconnect(self.WIRED)},
                                   {f"{NM_DEV}.Autoconnect": lambda _v: None})
            if self.wired_state() == 100:
                objects[NM_PATH + "/ActiveConnection/2"] = (NM_ACTIVE_NODE, lambda _i: self._active(False), {}, {})
        return objects

    def _conn_methods(self, ssid: str | None) -> dict[str, Callable[..., Any]]:
        def delete() -> None:
            if ssid and self.net()["wifi"]["connected"] == ssid:
                self.net()["wifi"]["connected"] = None
            if ssid in self.extra_saved:
                self.extra_saved.remove(ssid)
            self.changed()
        return {f"{NM_CONN}.GetSettings": lambda: self._conn_settings(ssid),
                f"{NM_CONN}.GetSecrets": lambda _s: V("(a{sa{sv}})", ({},)),
                f"{NM_CONN}.Update": lambda _s: None, f"{NM_CONN}.ClearSecrets": lambda: None,
                f"{NM_CONN}.Delete": delete}

    def sync(self) -> None:
        super().sync()
        for path in (self.WIFI, self.WIRED):
            now = (self.wifi_state() if path == self.WIFI else self.wired_state()) if path in self.objects else None
            old = self.published_state.get(path)
            if now is not None and old is not None and now != old:
                reason = self.device_state.get(path, (0, 0))[1]
                self.emit(path, NM_DEV, "StateChanged", "uuu", now, old, reason)
            self.published_state[path] = now

    def on_added(self, path: str, obj: Exported) -> None:
        if path in (self.WIFI, self.WIRED):
            self.emit(NM_PATH, NM, "DeviceAdded", "o", path)
        elif path.startswith(NM_PATH + "/AccessPoint/"):
            self.emit(self.WIFI, NM_WIFI, "AccessPointAdded", "o", path)

    def on_removed(self, path: str, obj: Exported) -> None:
        if path in (self.WIFI, self.WIRED):
            self.emit(NM_PATH, NM, "DeviceRemoved", "o", path)
        elif path.startswith(NM_PATH + "/AccessPoint/") and self.WIFI in self.objects:
            self.emit(self.WIFI, NM_WIFI, "AccessPointRemoved", "o", path)
        elif path.startswith(NM_PATH + "/ActiveConnection/"):
            self.emit(path, NM_ACTIVE, "StateChanged", "uu", 4, 2)
        elif path.startswith(self.SETTINGS + "/"):
            self.emit(path, NM_CONN, "Removed", "")
