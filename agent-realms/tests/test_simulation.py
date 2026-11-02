"""Simulation contracts: scenario files, fake D-Bus services on a real private bus, host glue.

The D-Bus tests run the fake services in-process against a throwaway dbus-daemon and
talk to them from a second connection, as Quickshell or busctl would. They need
PyGObject and dbus-daemon (both system packages here) and are skipped without them.
"""
from __future__ import annotations

import copy
import json
import shutil
import subprocess
import tempfile
import time
import unittest
import warnings
from pathlib import Path
from unittest.mock import patch

from cortetsu_agent_realms.paths import RealmError
from cortetsu_agent_realms.simulation import scenario as sc

# PyGObject's own asyncio shim warns on Python 3.14; unrelated to this code.
warnings.filterwarnings("ignore", category=DeprecationWarning, module="gi.events")

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    from cortetsu_agent_realms.simulation import services as svc
    HAVE_GI = shutil.which("dbus-daemon") is not None
except (ImportError, ValueError):
    HAVE_GI = False


class ScenarioTests(unittest.TestCase):
    def test_required_scenarios_match_the_specification(self) -> None:
        names = {s["name"] for s in sc.list_scenarios()}
        self.assertTrue({"battery-low", "charging", "gaming", "services-failing", "desktop"} <= names)

        low = sc.load_scenario("battery-low")["state"]
        self.assertEqual(low["upower"]["battery"]["percentage"], 12.0)
        self.assertFalse(low["upower"]["line_power"]["online"])
        self.assertEqual(low["power_profiles"]["active"], "power-saver")
        self.assertIsNotNone(low["network"]["wifi"]["connected"])
        self.assertFalse(low["bluetooth"]["adapter"]["powered"])

        charging = sc.load_scenario("charging")["state"]
        self.assertEqual((charging["upower"]["battery"]["percentage"], charging["upower"]["battery"]["state"]),
                         (96.0, "charging"))
        self.assertEqual(charging["power_profiles"]["active"], "balanced")
        self.assertTrue(charging["audio"]["available"] and charging["audio"]["sinks"])

        gaming = sc.load_scenario("gaming")["state"]
        self.assertTrue(gaming["upower"]["line_power"]["online"])
        self.assertEqual(gaming["power_profiles"]["active"], "performance")
        self.assertIn("performance", gaming["power_profiles"]["profiles"])
        pad = gaming["bluetooth"]["devices"][0]
        self.assertEqual((pad["icon"], pad["connected"]), ("input-gaming", True))

        failing = sc.load_scenario("services-failing")["state"]
        self.assertFalse(failing["network"]["available"])
        self.assertFalse(failing["upower"]["available"])
        self.assertTrue(failing["audio"]["restarting"])
        self.assertTrue(failing["bluetooth"]["fail_operations"])

        desktop = sc.load_scenario("desktop")["state"]
        self.assertFalse(desktop["upower"]["battery"]["present"])
        self.assertTrue(desktop["network"]["ethernet"]["connected"])
        self.assertFalse(desktop["network"]["wifi"]["present"])
        self.assertFalse(desktop["bluetooth"]["adapter"]["present"])
        self.assertTrue(desktop["audio"]["available"])

    def test_scenario_files_are_strict(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            cases = {
                "typo": {"schema": 1, "name": "typo", "description": "x", "state": {"upower": {"batery": {}}}},
                "old": {"schema": 0, "name": "old", "description": "x", "state": {}},
                "renamed": {"schema": 1, "name": "other", "description": "x", "state": {}},
                "extra": {"schema": 1, "name": "extra", "description": "x", "state": {}, "exec": "sh"},
                "range": {"schema": 1, "name": "range", "description": "x",
                          "state": {"upower": {"battery": {"percentage": 250}}}},
                "ghost": {"schema": 1, "name": "ghost", "description": "x",
                          "state": {"power_profiles": {"active": "performance", "profiles": ["balanced"]}}},
            }
            for name, document in cases.items():
                (folder / f"{name}.json").write_text(json.dumps(document))
                with self.assertRaises(sc.ScenarioError, msg=name):
                    sc.load_scenario(name, folder)
            with self.assertRaises(sc.ScenarioError):
                sc.load_scenario("../etc/passwd", folder)

    def test_assignments_validate_paths_types_and_injection(self) -> None:
        state = sc.load_scenario("charging")["state"]
        moved = sc.apply_assignment(state, "upower.battery.percentage=12")
        self.assertEqual(moved["upower"]["battery"]["percentage"], 12.0)
        self.assertEqual(state["upower"]["battery"]["percentage"], 96.0, "input state must not change")
        self.assertTrue(sc.apply_assignment(state, "audio.sinks.0.mute=true")["audio"]["sinks"][0]["mute"])
        self.assertIsNone(sc.apply_assignment(state, "network.wifi.connected=null")["network"]["wifi"]["connected"])
        for bad in ("upower.battery.percentage=101", "upower.battery=7", "nope=1", "audio.sinks.9.mute=true",
                    "upower..x=1", "power_profiles.active=turbo", "bluetooth.devices.0.address=\"zz\"",
                    'audio.sinks.0.description="x\\" media.class=Audio/Source"', "audio.default_sink=\"ghost\"",
                    "noequals"):
            with self.assertRaises(sc.ScenarioError, msg=bad):
                sc.apply_assignment(state, bad)


@unittest.skipUnless(HAVE_GI, "requires PyGObject and dbus-daemon")
class FakeServiceTests(unittest.TestCase):
    """Fake services on a private dbus-daemon, driven like a real client would."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="agent-realm-sim-test-")
        sock = Path(self.tmp.name) / "bus"
        config = Path(self.tmp.name) / "bus.conf"
        config.write_text(f"""<busconfig><type>system</type><listen>unix:path={sock}</listen>
            <auth>EXTERNAL</auth><policy context="default"><allow user="*"/><allow own="*"/>
            <allow send_destination="*"/><allow receive_sender="*"/></policy></busconfig>""")
        self.daemon = subprocess.Popen(["dbus-daemon", "--config-file", str(config), "--nofork", "--nopidfile"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 5
        while not sock.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
        self.server = Gio.DBusConnection.new_for_address_sync(f"unix:path={sock}", flags, None, None)
        self.client = Gio.DBusConnection.new_for_address_sync(f"unix:path={sock}", flags, None, None)
        self.state = copy.deepcopy(sc.load_scenario("charging")["state"])
        self.services: list = []
        self.signals: list[tuple[str, str, str, object]] = []
        self.client.signal_subscribe(None, None, None, None, None, Gio.DBusSignalFlags.NONE,
                                     lambda _c, _s, path, iface, name, params: self.signals.append(
                                         (path, iface, name, params.unpack())))

    def tearDown(self) -> None:
        for service in self.services:
            service.stop()
        self.server.close_sync(None)
        self.client.close_sync(None)
        self.daemon.terminate()
        self.daemon.wait(5)
        self.tmp.cleanup()

    def spin(self, until=lambda: False, timeout: float = 3.0) -> None:
        context = GLib.MainContext.default()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while context.iteration(False):
                pass
            if until():
                return
            time.sleep(0.005)

    def start(self, cls):
        def changed() -> None:
            GLib.idle_add(lambda: [s.sync() for s in self.services] and False)
        service = cls(self.server, lambda: self.state, changed)
        self.services.append(service)
        service.sync()
        self.spin(lambda: self.has_owner(service.bus_names[0]))
        return service

    def resync(self) -> None:
        for service in self.services:
            service.sync()
        self.spin(timeout=0.3)

    def call(self, dest: str, path: str, iface: str, method: str, params=None, expect_error: bool = False):
        box: dict = {}
        self.client.call(dest, path, iface, method, params, None, Gio.DBusCallFlags.NONE, 3000, None,
                         lambda conn, res: box.update(result=self._finish(conn, res)))
        self.spin(lambda: "result" in box)
        result = box.get("result")
        if isinstance(result, GLib.Error):
            if expect_error:
                return result
            raise AssertionError(f"{method}: {result.message}")
        if expect_error:
            raise AssertionError(f"{method} should have failed")
        return result.unpack() if result is not None else None

    @staticmethod
    def _finish(conn, res):
        try:
            return conn.call_finish(res)
        except GLib.Error as exc:
            return exc

    def get(self, dest: str, path: str, iface: str, name: str):
        return self.call(dest, path, "org.freedesktop.DBus.Properties", "Get",
                         GLib.Variant("(ss)", (iface, name)))[0]

    def has_owner(self, name: str) -> bool:
        box: dict = {}
        self.client.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                         GLib.Variant("(s)", (name,)), None, Gio.DBusCallFlags.NONE, 1000, None,
                         lambda c, r: box.update(v=c.call_finish(r).unpack()[0]))
        context = GLib.MainContext.default()
        deadline = time.monotonic() + 2
        while "v" not in box and time.monotonic() < deadline:
            context.iteration(False)
        return box.get("v", False)

    def changed_props(self, path: str) -> list[dict]:
        return [p[1] for (sp, _i, name, p) in self.signals if sp == path and name == "PropertiesChanged"]

    def test_upower_devices_transitions_and_disappearance(self) -> None:
        self.start(svc.UPower)
        dest, root = svc.UPOWER, svc.UPOWER_PATH
        devices = self.call(dest, root, svc.UPOWER, "EnumerateDevices")[0]
        self.assertEqual(devices, [svc.UPower.BATTERY, svc.UPower.AC])
        display = self.call(dest, root, svc.UPOWER, "GetDisplayDevice")[0]
        self.assertEqual(self.get(dest, display, svc.DEVICE_IFACE, "Percentage"), 96.0)
        self.assertEqual(self.get(dest, display, svc.DEVICE_IFACE, "State"), 1)
        self.assertEqual(self.get(dest, display, svc.DEVICE_IFACE, "Type"), 2)
        self.assertFalse(self.get(dest, root, svc.UPOWER, "OnBattery"))

        self.state["upower"]["battery"].update(percentage=12.0, state="discharging")
        self.state["upower"]["line_power"]["online"] = False
        self.resync()
        self.spin(lambda: any(c.get("Percentage") == 12.0 for c in self.changed_props(display)))
        self.assertTrue(any(c.get("Percentage") == 12.0 and c.get("State") == 2
                            for c in self.changed_props(display)))
        self.assertTrue(any(c.get("OnBattery") is True for c in self.changed_props(root)))

        self.state["upower"]["battery"]["present"] = False
        self.resync()
        self.spin(lambda: any(n == "DeviceRemoved" for (_p, _i, n, _a) in self.signals))
        self.assertIn((root, svc.UPOWER, "DeviceRemoved", (svc.UPower.BATTERY,)), self.signals)
        self.assertEqual(self.get(dest, display, svc.DEVICE_IFACE, "IsPresent"), False)

        self.state["upower"]["available"] = False
        self.resync()
        self.spin(lambda: not self.has_owner(dest))
        self.assertFalse(self.has_owner(dest))
        self.state["upower"]["available"] = True
        self.resync()
        self.spin(lambda: self.has_owner(dest))
        self.assertTrue(self.has_owner(dest))

    def test_power_profiles_accepts_and_rejects_changes(self) -> None:
        self.start(svc.PowerProfiles)
        dest, path, iface = svc.PP, svc.PP_PATH, svc.PP
        self.assertEqual(self.get(dest, path, iface, "ActiveProfile"), "balanced")
        profiles = [p["Profile"] for p in self.get(dest, path, iface, "Profiles")]
        self.assertEqual(profiles, ["power-saver", "balanced", "performance"])
        self.call(dest, path, "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", (iface, "ActiveProfile", GLib.Variant("s", "performance"))))
        self.spin(lambda: self.state["power_profiles"]["active"] == "performance")
        self.assertEqual(self.state["power_profiles"]["active"], "performance")
        self.state["power_profiles"]["reject_changes"] = True
        self.call(dest, path, "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", (iface, "ActiveProfile", GLib.Variant("s", "power-saver"))),
                  expect_error=True)
        self.assertEqual(self.state["power_profiles"]["active"], "performance")
        self.assertTrue(self.has_owner("net.hadess.PowerProfiles"))

    def test_network_manager_devices_scan_connect_and_failure(self) -> None:
        nm = self.start(svc.NetworkManager)
        dest, root = svc.NM, svc.NM_PATH
        devices = self.call(dest, root, svc.NM, "GetAllDevices")[0]
        self.assertEqual(devices, [svc.NetworkManager.WIFI])
        wifi = devices[0]
        self.assertEqual(self.get(dest, wifi, svc.NM_DEV, "DeviceType"), 2)
        self.assertEqual(self.get(dest, wifi, svc.NM_DEV, "State"), 100)
        aps = self.call(dest, wifi, svc.NM_WIFI, "GetAllAccessPoints")[0]
        ssids = [bytes(self.get(dest, ap, svc.NM_AP, "Ssid")).decode() for ap in aps]
        self.assertEqual(ssids, ["CortetsuLab", "Cafe Libre"])
        self.assertEqual(self.get(dest, root, svc.NM, "Connectivity"), 4)

        self.call(dest, wifi, svc.NM_WIFI, "RequestScan", GLib.Variant("(a{sv})", ({},)))
        self.spin(lambda: any(n == "AccessPointAdded" for (_p, _i, n, _a) in self.signals))
        self.assertEqual(len(self.call(dest, wifi, svc.NM_WIFI, "GetAllAccessPoints")[0]), 3)

        self.call(dest, wifi, svc.NM_DEV, "Disconnect")
        self.spin(lambda: self.get(dest, wifi, svc.NM_DEV, "State") == 30)
        self.assertIsNone(self.state["network"]["wifi"]["connected"])
        saved = self.call(dest, svc.NetworkManager.SETTINGS, svc.NM_SETTINGS, "ListConnections")[0]
        self.assertEqual(len(saved), 1, "disconnecting keeps the saved profile")

        ap = self.call(dest, wifi, svc.NM_WIFI, "GetAllAccessPoints")[0][1]
        self.call(dest, root, svc.NM, "ActivateConnection", GLib.Variant("(ooo)", ("/", wifi, ap)))
        self.spin(lambda: self.state["network"]["wifi"]["connected"] == "Cafe Libre", timeout=3)
        self.assertEqual(self.state["network"]["wifi"]["connected"], "Cafe Libre")
        self.assertEqual(self.get(dest, wifi, svc.NM_DEV, "State"), 100)

        self.state["network"]["wifi"]["fail_connect"] = True
        self.signals.clear()
        self.call(dest, root, svc.NM, "ActivateConnection", GLib.Variant("(ooo)", ("/", wifi, aps[0])))
        self.spin(lambda: any(n == "StateChanged" and a[0] == 120 for (_p, _i, n, a) in self.signals), timeout=3)
        failed = [a for (p, _i, n, a) in self.signals if p == wifi and n == "StateChanged"]
        self.assertIn(120, [a[0] for a in failed], "activation must pass through FAILED")
        self.assertEqual(failed[-1][2], 7, "reason NO_SECRETS")
        self.spin(lambda: self.state["network"]["wifi"]["connected"] is None, timeout=3)
        self.assertIsNone(self.state["network"]["wifi"]["connected"])

        self.call(dest, root, "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", (svc.NM, "WirelessEnabled", GLib.Variant("b", False))))
        self.spin(lambda: not self.state["network"]["wireless_enabled"])
        self.assertFalse(self.state["network"]["wireless_enabled"])
        self.assertEqual(nm.wifi_state(), 20)

        self.state["network"]["available"] = False
        self.resync()
        self.spin(lambda: not self.has_owner(dest))
        self.assertFalse(self.has_owner(dest))

    def test_bluez_object_manager_power_discovery_pairing_and_errors(self) -> None:
        self.start(svc.BlueZ)
        dest = svc.BLUEZ
        objects = self.call(dest, "/", svc.OM, "GetManagedObjects")[0]
        self.assertIn(svc.HCI, objects)
        self.assertIn("org.bluez.Battery1", objects[f"{svc.HCI}/dev_AA_BB_CC_00_00_01"])
        self.assertTrue(objects[svc.HCI][svc.ADAPTER]["Powered"])

        self.call(dest, svc.HCI, "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", (svc.ADAPTER, "Powered", GLib.Variant("b", False))))
        self.spin(lambda: self.get(dest, svc.HCI, svc.ADAPTER, "PowerState") == "off")
        self.assertFalse(self.state["bluetooth"]["adapter"]["powered"])
        error = self.call(dest, svc.HCI, svc.ADAPTER, "StartDiscovery", expect_error=True)
        self.assertIn("NotReady", error.message)

        self.state["bluetooth"]["adapter"]["powered"] = True
        self.resync()
        self.call(dest, svc.HCI, svc.ADAPTER, "StartDiscovery")
        self.spin(lambda: any(n == "InterfacesAdded" for (_p, _i, n, _a) in self.signals), timeout=2)
        added = [a[0] for (_p, _i, n, a) in self.signals if n == "InterfacesAdded"]
        self.assertIn(f"{svc.HCI}/dev_AA_BB_CC_00_00_02", added)
        keyboard = f"{svc.HCI}/dev_AA_BB_CC_00_00_02"
        self.call(dest, keyboard, svc.DEVICE1, "Pair")
        self.call(dest, keyboard, svc.DEVICE1, "Connect")
        self.spin(lambda: self.get(dest, keyboard, svc.DEVICE1, "Connected") is True)
        self.assertTrue(self.get(dest, keyboard, svc.DEVICE1, "Paired"))

        self.state["bluetooth"]["fail_operations"] = True
        for method_name in ("Connect", "Pair"):
            error = self.call(dest, keyboard, svc.DEVICE1, method_name, expect_error=True)
            self.assertIn("org.bluez.Error", error.message)
        self.call(dest, svc.HCI, "org.freedesktop.DBus.Properties", "Set",
                  GLib.Variant("(ssv)", (svc.ADAPTER, "Powered", GLib.Variant("b", False))), expect_error=True)
        self.assertTrue(self.state["bluetooth"]["adapter"]["powered"])

        self.state["bluetooth"]["adapter"]["present"] = False
        self.resync()
        self.spin(lambda: any(n == "InterfacesRemoved" and a[0] == svc.HCI for (_p, _i, n, a) in self.signals))
        self.assertNotIn(svc.HCI, self.call(dest, "/", svc.OM, "GetManagedObjects")[0])


class HostGlueTests(unittest.TestCase):
    def _call_with_output(self, stdout: bytes):
        from cortetsu_agent_realms.simulation import host
        with patch.object(host, "_live_meta", return_value={}), \
             patch.object(host.runtime, "realm_bwrap", return_value=["bwrap", "--"]), \
             patch.object(host.runtime, "_manager_env", return_value={}), \
             patch.object(host, "paths_for"), \
             patch.object(host.subprocess, "run",
                          return_value=subprocess.CompletedProcess([], 0, stdout, b"")) as run:
            return host.call("codex", "State"), run

    def test_realm_output_is_bounded_and_validated(self) -> None:
        reply, run = self._call_with_output(b'{"scenario": "charging"}')
        self.assertEqual(reply, {"scenario": "charging"})
        argv = run.call_args.args[0]
        self.assertEqual(argv[-1], "State")
        self.assertIn("cortetsu_agent_realms.simulation.ctl", argv)
        for garbage in (b"", b"not json", b"[1, 2]", b'{"error": "boom"}', b"{" + b" " * (2 * 1024 * 1024)):
            with self.assertRaises(RealmError, msg=garbage[:20]):
                self._call_with_output(garbage)

    def test_realm_points_at_its_own_system_bus_never_the_host_one(self) -> None:
        from cortetsu_agent_realms.paths import RealmPaths
        from cortetsu_agent_realms.runtime import _bwrap_prefix, _runtime_env
        paths = RealmPaths("codex", Path("/s"), Path("/h"), Path("/tmp/ar-1-abc"), Path("/c"), Path("/l"),
                           Path("/hl"), control=Path("/ctl"))
        address = _runtime_env(paths)["DBUS_SYSTEM_BUS_ADDRESS"]
        self.assertEqual(address, "unix:path=/tmp/ar-1-abc/system_bus_socket")
        with patch("cortetsu_agent_realms.runtime.shutil.which", return_value="/usr/bin/bwrap"):
            args = _bwrap_prefix(paths)
        mounted = {args[i + 2] for i, a in enumerate(args) if a in ("--bind", "--ro-bind", "--dev-bind")}
        self.assertFalse(any(m == "/run" or m.startswith("/run/") for m in mounted), mounted)
        self.assertNotIn("/dev/snd", mounted)

    def test_simulator_sandbox_sees_only_code_and_scenarios(self) -> None:
        from cortetsu_agent_realms import runtime
        from cortetsu_agent_realms.paths import RealmPaths
        paths = RealmPaths("codex", Path("/s"), Path("/h"), Path("/tmp/ar-1-abc"), Path("/c"), Path("/l"),
                           Path("/hl"), control=Path("/ctl"))
        meta = {"signature": "abc_1", "wayland_display": "wayland-1"}
        with patch("cortetsu_agent_realms.runtime.shutil.which", return_value="/usr/bin/bwrap"):
            args = runtime.realm_bwrap(paths, meta, mount_project=True)
        binds = [(args[i + 1], args[i + 2]) for i, a in enumerate(args) if a == "--ro-bind"]
        root = runtime.repo_root()
        project = [(src, dst) for src, dst in binds if dst.startswith("/app")]
        self.assertEqual(project, [(str(root / "src"), "/app/src"), (str(root / "scenarios"), "/app/scenarios")])
        self.assertNotIn(str(root), [src for src, _dst in binds])
        self.assertEqual(args[-1], "--")

    def test_simulate_cli_flags(self) -> None:
        from cortetsu_agent_realms.cli import parser
        args = parser().parse_args(["simulate", "codex", "--scenario", "battery-low",
                                    "--set", "upower.battery.percentage=50", "--event", "wifi-scan"])
        self.assertEqual((args.name, args.scenario, args.set, args.event),
                         ("codex", "battery-low", ["upower.battery.percentage=50"], "wifi-scan"))
        self.assertTrue(parser().parse_args(["simulate", "--list"]).list)


@unittest.skipUnless(HAVE_GI, "PyGObject no disponible")
class AudioMonitorTests(unittest.TestCase):
    """The pw-metadata monitor is read on the simulator's only main loop."""

    def _audio(self, state):
        from cortetsu_agent_realms.simulation.audio import Audio
        with patch.dict("os.environ", {"XDG_RUNTIME_DIR": tempfile.gettempdir()}):
            return Audio(lambda: state, lambda: None, Path(tempfile.gettempdir()))

    def test_partial_line_and_stale_monitor_never_block(self) -> None:
        import os
        state = {"audio": {"sinks": [{"name": "b"}], "sources": [], "default_sink": "a", "default_source": ""}}
        audio = self._audio(state)
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, read_fd)
        os.set_blocking(read_fd, False)
        monitor = object()
        audio.monitor = monitor
        line = b"update: id:0 key:'default.configured.audio.sink' value:'{\"name\":\"b\"}' type:'Spa:String:JSON'\n"
        os.write(write_fd, line[:20])
        started = time.monotonic()
        self.assertTrue(audio._on_metadata(read_fd, GLib.IO_IN, monitor))  # partial line
        self.assertTrue(audio._on_metadata(read_fd, GLib.IO_IN, monitor))  # nothing to read
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(state["audio"]["default_sink"], "a")
        os.write(write_fd, line[20:])
        self.assertTrue(audio._on_metadata(read_fd, GLib.IO_IN, monitor))
        self.assertEqual(state["audio"]["default_sink"], "b")
        self.assertFalse(audio._on_metadata(read_fd, GLib.IO_IN, object()))  # watch of a replaced monitor
        os.close(write_fd)
        self.assertFalse(audio._on_metadata(read_fd, GLib.IO_HUP, monitor))  # EOF


if __name__ == "__main__":
    unittest.main()
