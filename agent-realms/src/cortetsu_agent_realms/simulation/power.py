"""Fake UPower and power-profiles-daemon, as read by Quickshell's UPower module."""
from __future__ import annotations



from .dbus import V, Exported, Service, iface, method, node, prop, signal


# -- UPower -------------------------------------------------------------------------------

UPOWER = "org.freedesktop.UPower"
UPOWER_PATH = "/org/freedesktop/UPower"
DEVICE_IFACE = "org.freedesktop.UPower.Device"
UPOWER_NODE = node(iface(UPOWER, "".join([
    method("EnumerateDevices", outs="ao"), method("GetDisplayDevice", outs="o"),
    method("GetCriticalAction", outs="s"), signal("DeviceAdded", "o"), signal("DeviceRemoved", "o"),
    prop("DaemonVersion", "s"), prop("OnBattery", "b"), prop("LidIsClosed", "b"), prop("LidIsPresent", "b")])))
DEVICE_NODE = node(iface(DEVICE_IFACE, method("Refresh") + "".join(prop(n, t) for n, t in (
    ("NativePath", "s"), ("Vendor", "s"), ("Model", "s"), ("Serial", "s"), ("UpdateTime", "t"),
    ("Type", "u"), ("PowerSupply", "b"), ("Online", "b"), ("Energy", "d"), ("EnergyEmpty", "d"),
    ("EnergyFull", "d"), ("EnergyFullDesign", "d"), ("EnergyRate", "d"), ("Voltage", "d"),
    ("TimeToEmpty", "x"), ("TimeToFull", "x"), ("Percentage", "d"), ("IsPresent", "b"), ("State", "u"),
    ("IsRechargeable", "b"), ("Capacity", "d"), ("Technology", "u"), ("WarningLevel", "u"),
    ("BatteryLevel", "u"), ("IconName", "s")))))
BATTERY_STATES = {"unknown": 0, "charging": 1, "discharging": 2, "empty": 3, "fully-charged": 4,
                  "pending-charge": 5, "pending-discharge": 6}


def battery_icon(percentage: float, charging: bool) -> str:
    level = min(100, int(round(percentage / 10.0)) * 10)
    return f"battery-level-{level}{'-charging' if charging else ''}-symbolic"


class UPower(Service):
    bus_names = (UPOWER,)
    DISPLAY = UPOWER_PATH + "/devices/DisplayDevice"
    BATTERY = UPOWER_PATH + "/devices/battery_BAT0"
    AC = UPOWER_PATH + "/devices/line_power_AC"

    @property
    def available(self) -> bool:
        return self.state()["upower"]["available"]

    def on_battery(self) -> bool:
        s = self.state()["upower"]
        return s["battery"]["present"] and not s["line_power"]["online"]

    def _battery_props(self, display: bool) -> dict[str, V]:
        b = self.state()["upower"]["battery"]
        present = b["present"]
        state = BATTERY_STATES[b["state"]] if present else 0
        energy_full = b["energy_full"]
        warning = 1 if not present else 4 if b["percentage"] <= 5 else 3 if b["percentage"] <= 10 else \
            2 if b["percentage"] <= 20 and b["state"] == "discharging" else 1
        rate = 0.0 if not present or b["state"] in {"fully-charged", "unknown"} else 9.5
        return {
            "NativePath": V("s", "" if display else "BAT0"), "Vendor": V("s", "Agent Realms"),
            "Model": V("s", "" if display else "Batería simulada"), "Serial": V("s", "SIM-0001"),
            "UpdateTime": V("t", 0), "Type": V("u", 2 if present else 0), "PowerSupply": V("b", present),
            "Online": V("b", False), "Energy": V("d", energy_full * b["percentage"] / 100 if present else 0.0),
            "EnergyEmpty": V("d", 0.0), "EnergyFull": V("d", energy_full if present else 0.0),
            "EnergyFullDesign": V("d", energy_full * 100 / b["capacity"] if present and b["capacity"] else 0.0),
            "EnergyRate": V("d", rate), "Voltage": V("d", 12.4 if present else 0.0),
            "TimeToEmpty": V("x", b["time_to_empty"] if present else 0),
            "TimeToFull": V("x", b["time_to_full"] if present else 0),
            "Percentage": V("d", b["percentage"] if present else 0.0), "IsPresent": V("b", present),
            "State": V("u", state), "IsRechargeable": V("b", present),
            "Capacity": V("d", b["capacity"] if present else 0.0), "Technology": V("u", 1 if present else 0),
            "WarningLevel": V("u", warning), "BatteryLevel": V("u", 1),
            "IconName": V("s", battery_icon(b["percentage"], state in {1, 4, 5}) if present
                          else "battery-missing-symbolic"),
        }

    def _ac_props(self) -> dict[str, V]:
        online = self.state()["upower"]["line_power"]["online"]
        base = {k: v for k, v in self._battery_props(False).items()}
        base.update({"NativePath": V("s", "AC"), "Model": V("s", ""), "Type": V("u", 1),
                     "PowerSupply": V("b", True), "Online": V("b", online), "IsPresent": V("b", False),
                     "State": V("u", 0), "Percentage": V("d", 0.0), "IsRechargeable": V("b", False),
                     "IconName": V("s", "ac-adapter-symbolic"), "Energy": V("d", 0.0),
                     "EnergyFull": V("d", 0.0), "TimeToEmpty": V("x", 0), "TimeToFull": V("x", 0)})
        return base

    def device_paths(self) -> list[str]:
        s = self.state()["upower"]
        return ([self.BATTERY] if s["battery"]["present"] else []) + \
            ([self.AC] if s["line_power"]["present"] else [])

    def build(self):
        root_props = lambda _i: {"DaemonVersion": V("s", "1.90.10"), "OnBattery": V("b", self.on_battery()),
                                 "LidIsClosed": V("b", False),
                                 "LidIsPresent": V("b", self.state()["upower"]["battery"]["present"])}
        methods = {f"{UPOWER}.EnumerateDevices": lambda: V("(ao)", (self.device_paths(),)),
                   f"{UPOWER}.GetDisplayDevice": lambda: V("(o)", (self.DISPLAY,)),
                   f"{UPOWER}.GetCriticalAction": lambda: V("(s)", ("PowerOff",))}
        refresh = {f"{DEVICE_IFACE}.Refresh": lambda: None}
        objects = {UPOWER_PATH: (UPOWER_NODE, root_props, methods, {}),
                   self.DISPLAY: (DEVICE_NODE, lambda _i: self._battery_props(True), refresh, {})}
        if self.BATTERY in self.device_paths():
            objects[self.BATTERY] = (DEVICE_NODE, lambda _i: self._battery_props(False), refresh, {})
        if self.AC in self.device_paths():
            objects[self.AC] = (DEVICE_NODE, lambda _i: self._ac_props(), refresh, {})
        return objects

    def on_added(self, path: str, obj: Exported) -> None:
        if path in (self.BATTERY, self.AC):
            self.emit(UPOWER_PATH, UPOWER, "DeviceAdded", "o", path)

    def on_removed(self, path: str, obj: Exported) -> None:
        if path in (self.BATTERY, self.AC):
            self.emit(UPOWER_PATH, UPOWER, "DeviceRemoved", "o", path)


# -- power-profiles-daemon ----------------------------------------------------------------

PP = "org.freedesktop.UPower.PowerProfiles"
PP_PATH = "/org/freedesktop/UPower/PowerProfiles"
PP_NODE = node(iface(PP, "".join([
    method("HoldProfile", "sss", "u"), method("ReleaseProfile", "u"), signal("ProfileReleased", "u"),
    prop("ActiveProfile", "s", "readwrite"), prop("PerformanceInhibited", "s"),
    prop("PerformanceDegraded", "s"), prop("Profiles", "aa{sv}"), prop("Actions", "as"),
    prop("ActiveProfileHolds", "aa{sv}"), prop("Version", "s")])))


class PowerProfiles(Service):
    bus_names = (PP, "net.hadess.PowerProfiles")

    @property
    def available(self) -> bool:
        return self.state()["power_profiles"]["available"]

    def _props(self, _iface: str) -> dict[str, V]:
        p = self.state()["power_profiles"]
        profiles = [{"Profile": V("s", name), "Driver": V("s", "placeholder" if name != "performance"
                                                          else "platform_profile"),
                     "PlatformDriver": V("s", "placeholder")} for name in p["profiles"]]
        return {"ActiveProfile": V("s", p["active"]), "PerformanceInhibited": V("s", ""),
                "PerformanceDegraded": V("s", p["degraded"]), "Profiles": V("aa{sv}", profiles),
                "Actions": V("as", []), "ActiveProfileHolds": V("aa{sv}", []), "Version": V("s", "0.30")}

    def _set_active(self, value: str) -> str | None:
        p = self.state()["power_profiles"]
        if p["reject_changes"] or value not in p["profiles"]:
            return "rechazado"
        p["active"] = value
        self.changed()
        return None

    def build(self):
        methods = {f"{PP}.HoldProfile": lambda *_a: V("(u)", (1,)), f"{PP}.ReleaseProfile": lambda _c: None}
        return {PP_PATH: (PP_NODE, self._props, methods, {f"{PP}.ActiveProfile": self._set_active})}
