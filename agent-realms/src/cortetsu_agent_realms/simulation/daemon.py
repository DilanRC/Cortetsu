"""In-realm simulation daemon: private system bus, fake services, private PipeWire.

Started by the host inside the realm's bwrap sandbox and systemd scope, so
`agent-realm stop` collects it with every other realm process. It never sees the
host's system bus, PipeWire or devices: none of them are mounted in the realm.

Control lives on the private bus as org.cortetsu.AgentRealms.Simulator. Realm apps
can reach it too; they can only change their own simulated world, never host state.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from gi.repository import Gio, GLib

from . import scenario as sc
from .audio import Audio
from .services import BlueZ, DBusFailure, NetworkManager, PowerProfiles, UPower, V, iface, method, node

CONTROL_NAME = "org.cortetsu.AgentRealms.Simulator"
CONTROL_PATH = "/org/cortetsu/AgentRealms/Simulator"
CONTROL_NODE = node(iface(CONTROL_NAME, "".join([
    method("Apply", "s", "s"), method("Set", "as", "s"), method("Event", "s", "s"),
    method("State", outs="s"), method("Reset", outs="s")])))
BUS_CONFIG = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path={socket}</listen>
  <auth>EXTERNAL</auth>
  <limit name="max_completed_connections">64</limit>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
"""


def system_bus_socket() -> Path:
    return Path(os.environ["XDG_RUNTIME_DIR"]) / "system_bus_socket"


class Simulator:
    def __init__(self, workdir: Path, scenario_name: str):
        self.workdir = workdir
        self.scenario_name = scenario_name
        self.state: dict[str, Any] = sc.load_scenario(scenario_name)["state"]
        self.loop = GLib.MainLoop()
        self.bus_proc = self._start_bus()
        self.bus = Gio.DBusConnection.new_for_address_sync(
            f"unix:path={system_bus_socket()}",
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        getter = lambda: self.state
        self.services = [cls(self.bus, getter, self.changed) for cls in (UPower, PowerProfiles, NetworkManager, BlueZ)]
        self.network = self.services[2]
        self.bluez = self.services[3]
        self.audio = Audio(getter, self.changed, workdir)
        self.pending = 0
        self.errors: list[str] = []
        self.bus.register_object(CONTROL_PATH, CONTROL_NODE.interfaces[0], self._control, None, None)
        Gio.bus_own_name_on_connection(self.bus, CONTROL_NAME, Gio.BusNameOwnerFlags.NONE, None, None)

    def _start_bus(self) -> subprocess.Popen[bytes]:
        socket_path = system_bus_socket()
        socket_path.unlink(missing_ok=True)
        config = self.workdir / "system-bus.conf"
        config.write_text(BUS_CONFIG.format(socket=socket_path))
        proc = subprocess.Popen(["/usr/bin/dbus-daemon", "--config-file", str(config), "--nofork", "--nopidfile",
                                 "--nosyslog"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=(self.workdir / "system-bus.log").open("ab"), close_fds=True)
        deadline = time.monotonic() + 5
        while not socket_path.exists():
            if proc.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("el bus de sistema privado no arrancó")
            time.sleep(0.02)
        return proc

    # -- state propagation ----------------------------------------------------------------

    def changed(self) -> None:
        """Coalesce changes; D-Bus handlers must return before signals go out."""
        if not self.pending:
            self.pending = GLib.idle_add(self.sync)

    def sync(self) -> bool:
        self.pending = 0
        for part in (*self.services, self.audio):
            try:
                part.sync()
            except Exception as exc:  # one broken service must not stop the others
                self.errors = (self.errors + [f"{type(part).__name__}: {exc}"])[-10:]
                print(f"agent-realm sim: {type(part).__name__}: {exc}", file=sys.stderr, flush=True)
        return False

    def snapshot(self) -> dict[str, Any]:
        return {"scenario": self.scenario_name, "state": self.state, "audio_live": self.audio.live_status(),
                "errors": self.errors}

    # -- control interface ------------------------------------------------------------------

    def _control(self, _bus, _sender, _path, _iface, name, params, invocation) -> None:
        try:
            args = params.unpack()
            if name == "Apply":
                loaded = sc.load_scenario(args[0])
                self.state.clear()
                self.state.update(loaded["state"])
                self.scenario_name = loaded["name"]
            elif name == "Set":
                new_state = self.state
                for assignment in args[0]:
                    new_state = sc.apply_assignment(new_state, assignment)
                self.state.clear()
                self.state.update(new_state)
            elif name == "Event":
                self._event(args[0])
            elif name == "Reset":
                self.state.clear()
                self.state.update(sc.load_scenario(self.scenario_name)["state"])
            if name != "State":
                self.sync()  # reply with the applied state, not the pending one
            invocation.return_value(V("(s)", (json.dumps(self.snapshot(), ensure_ascii=False),)))
        except (sc.ScenarioError, DBusFailure, ValueError) as exc:
            invocation.return_dbus_error(f"{CONTROL_NAME}.Error.Invalid", str(getattr(exc, "message", exc)))

    def _event(self, event: str) -> None:
        if event == "wifi-scan":
            if not (self.state["network"]["available"] and self.state["network"]["wifi"]["present"]):
                raise ValueError("no hay NetworkManager con Wi-Fi para escanear")
            self.network.request_scan()
        elif event == "bt-discover":
            if not (self.state["bluetooth"]["available"] and self.state["bluetooth"]["adapter"]["present"]):
                raise ValueError("no hay adaptador Bluetooth")
            self.bluez._discovery(True)
        elif event == "pipewire-restart":
            self.state["audio"]["restarting"] = True
        else:
            raise ValueError(f"evento desconocido; usa {', '.join(sc.EVENTS)}")

    # -- lifecycle --------------------------------------------------------------------------

    def run(self) -> int:
        for sig in (signal.SIGTERM, signal.SIGINT):
            GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, self.loop.quit)
        GLib.timeout_add_seconds(1, self._watch_bus)
        self.sync()
        print(f"agent-realm sim: escenario {self.scenario_name} activo", file=sys.stderr, flush=True)
        try:
            self.loop.run()
        finally:
            for service in self.services:
                service.stop()
            self.audio.stop_daemon()
            self.bus_proc.terminate()
            self.bus_proc.wait(timeout=3)
            system_bus_socket().unlink(missing_ok=True)
        return 0

    def _watch_bus(self) -> bool:
        if self.bus_proc.poll() is not None:
            print("agent-realm sim: el bus privado terminó", file=sys.stderr, flush=True)
            self.loop.quit()
            return False
        return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cortetsu_agent_realms.simulation.daemon")
    parser.add_argument("--scenario", required=True)
    args = parser.parse_args(argv)
    workdir = Path(os.environ["XDG_RUNTIME_DIR"]) / "agent-realm-sim"
    workdir.mkdir(mode=0o700, exist_ok=True)
    try:
        return Simulator(workdir, args.scenario).run()
    except (sc.ScenarioError, RuntimeError, GLib.Error) as exc:
        print(f"agent-realm sim: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
