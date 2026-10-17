"""Nested Hyprland + isolated Cortetsu shell + virtual input, for launcher tests.

Everything runs against a throwaway compositor: its own XDG_RUNTIME_DIR, a
temporary HOME, a private D-Bus session bus, and a virtual keyboard/pointer
that connect only to the nested WAYLAND_DISPLAY. The desktop session never
receives an event. Startup programs from the Lua config are not run.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

from nested_gpu import MESA_ONLY, compositor_env

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
HYPRCTL = os.environ.get("CORTETSU_TEST_HYPRCTL") or shutil.which("hyprctl") or "hyprctl"

# evdev codes
KEY_LEFTMETA, KEY_ESC, KEY_A, KEY_E, KEY_DOWN, KEY_RIGHT, KEY_RETURN = 125, 1, 30, 18, 108, 106, 28
KEY_1 = 2
BTN_LEFT = 272


def wait_for(predicate, what: str, timeout: float = 20.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(f"timeout esperando: {what}")


def missing_tools() -> list[str]:
    return [tool for tool in ("Hyprland", "qs", "cc", "wayland-scanner", "pkg-config", "dbus-daemon")
            if not shutil.which(tool)]


def build_vinput(out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    for proto in ("virtual-keyboard-unstable-v1", "wlr-virtual-pointer-unstable-v1"):
        xml = HERE / "protocols" / f"{proto}.xml"
        subprocess.run(["wayland-scanner", "client-header", xml, out / f"{proto}-client-protocol.h"], check=True)
        subprocess.run(["wayland-scanner", "private-code", xml, out / f"{proto}-protocol.c"], check=True)
    flags = subprocess.run(["pkg-config", "--cflags", "--libs", "wayland-client", "xkbcommon"],
                           check=True, text=True, capture_output=True).stdout.split()
    binary = out / "vinput"
    subprocess.run(["cc", "-O1", "-Wall", f"-I{out}", str(HERE / "vinput.c"),
                    *map(str, out.glob("*-protocol.c")), "-o", str(binary), *flags], check=True)
    return binary


def compose_runtime(destination: Path) -> Path:
    """Same layout build-runtime.sh produces, without its regression suite."""
    src = REPO / "cortetsu"
    shutil.copytree(src / "base", destination, symlinks=True)
    for name in ("modules", "components", "utils", "services", "theme"):
        shutil.copytree(src / name, destination / name, symlinks=True, dirs_exist_ok=True)
    shutil.copy(src / "shell.qml", destination / "shell.qml")
    shutil.copytree(src / "assets/branding", destination / "assets/branding", dirs_exist_ok=True)
    (destination / "base/modules/bar").mkdir(parents=True, exist_ok=True)
    shutil.copy(src / "base/modules/bar/SystemTrayIdentity.js", destination / "base/modules/bar/SystemTrayIdentity.js")
    subprocess.run(["python3", str(src / "bin/compose-panels.py"), str(destination)], check=True,
                   stdout=subprocess.DEVNULL)
    return destination


def write_hypr_config(home: Path) -> None:
    generation = home.parent / "generation/home/.config/hypr"
    shutil.copytree(REPO / "dotfiles/home/.config/hypr", generation, symlinks=True)
    shutil.copy(REPO / "config/hypr-user.lua", generation / "hypr-user.lua")
    hypr = home / ".config/hypr"
    hypr.mkdir(parents=True)
    for entry in generation.iterdir():
        if entry.name != "hyprland.lua":
            (hypr / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    (hypr / "hyprland.lua").write_text(
        "-- Test loader: no startup programs, and binds never run programs.\n"
        "hl.exec_cmd = function() end\n"
        'local cortetsu_noop = hl.dsp.exec_cmd("true")\n'
        "hl.dsp.exec_cmd = function() return cortetsu_noop end\n"
        f'dofile("{generation}/hyprland.lua")\n'
        # Same release semantics, no animations to wait for.
        'hl.config({ animations = { enabled = false }, misc = { disable_hyprland_logo = true } })\n'
        # Side by side, never overlapping: the nested window and extra outputs.
        'hl.monitor({ output = "WAYLAND-1", mode = "preferred", position = "0x0", scale = 1 })\n'
        'hl.monitor({ output = "HEADLESS-1", mode = "1280x720", position = "auto-right", scale = 1 })\n'
        'hl.monitor({ output = "HEADLESS-2", mode = "1280x720", position = "auto-right", scale = 1 })\n'
        # The desktop's own keyboard and pointer reach the nested compositor
        # when the real pointer crosses its window; Hyprland ORs every
        # keyboard's modifiers into bind matching, so a real Super would leak
        # into the test. Only the virtual devices drive it.
        'hl.device({ name = "wl_keyboard", enabled = false })\n'
        'hl.device({ name = "wl_pointer", enabled = false })\n')


class Session:
    def __init__(self, base: Path):
        self.base = base
        self.home = base / "home"
        self.runtime = base / "run"
        self.runtime.mkdir(mode=0o700)
        self.logs = base / "logs"
        self.logs.mkdir()
        write_hypr_config(self.home)
        shell = compose_runtime(self.home / ".config/quickshell/cortetsu/gen")
        (self.home / ".config/quickshell/cortetsu/current").symlink_to(shell)
        self.shell_dir = self.home / ".config/quickshell/cortetsu/current"
        self.vinput_bin = build_vinput(base / "vinput")
        self.launches = base / "launches.log"
        self.write_fixtures()
        self.compositor = self.shell = self.input = self.bus = self.client = None

    def write_fixtures(self) -> None:
        """Fixture applications and a launcher stub that only records argv.

        PATH holds the stub and the system binaries, never ~/.local/bin, so no
        real Cortetsu helper (scopes, brightness, vibrance) runs from here.
        """
        bin_dir = self.base / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "cortetsu-launch-persistent"
        stub.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{self.launches}"\n')
        stub.chmod(0o755)
        apps = self.base / "share/applications"
        apps.mkdir(parents=True)
        for index in range(6):
            (apps / f"probe{index}.desktop").write_text(
                "[Desktop Entry]\nType=Application\n"
                f"Name=Probe {index}\nExec=/bin/true probe{index}\nIcon=application-x-executable\n")

    # environment -------------------------------------------------------
    def env(self) -> dict:
        signature = next((self.runtime / "hypr").iterdir()).name
        return {
            "HOME": str(self.home), "PATH": f"{self.base / 'bin'}:/usr/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
            "XDG_DATA_DIRS": str(self.base / "share"),
            "XDG_RUNTIME_DIR": str(self.runtime), "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_STATE_HOME": str(self.home / ".local/state"), "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_CACHE_HOME": str(self.home / ".cache"), "WAYLAND_DISPLAY": self.socket,
            "HYPRLAND_INSTANCE_SIGNATURE": signature, "QT_QPA_PLATFORM": "wayland",
            "XDG_CURRENT_DESKTOP": "Hyprland", "QT_QUICK_BACKEND": "software",
            "DBUS_SESSION_BUS_ADDRESS": self.bus_address, "QT_NO_XDG_DESKTOP_PORTAL": "1",
            **MESA_ONLY,
        }

    def start_bus(self) -> None:
        # No <servicedir>: nothing is ever bus-activated (portals, notifiers),
        # so the shell's session-bus services only talk to each other.
        config = self.base / "bus.conf"
        config.write_text(
            "<!DOCTYPE busconfig PUBLIC \"-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN\" "
            "\"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd\">\n"
            f"<busconfig><type>session</type><listen>unix:path={self.base}/bus</listen>"
            "<policy context=\"default\"><allow send_destination=\"*\" eavesdrop=\"true\"/>"
            "<allow eavesdrop=\"true\"/><allow own=\"*\"/></policy></busconfig>\n")
        self.bus = subprocess.Popen(["dbus-daemon", f"--config-file={config}", "--nofork", "--print-address"],
                                    stdout=subprocess.PIPE, text=True, start_new_session=True,
                                    env=dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime)))
        self.bus_address = self.bus.stdout.readline().strip()
        assert self.bus_address, "dbus-daemon de prueba no arrancó"

    def start(self, outputs: int = 1) -> None:
        self.start_bus()
        parent = os.environ["WAYLAND_DISPLAY"]
        parent_socket = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
        env = {"HOME": str(self.home), "PATH": os.environ["PATH"], "LANG": "C.UTF-8",
               "XDG_RUNTIME_DIR": str(self.runtime), "WAYLAND_DISPLAY": parent_socket}
        self.compositor = subprocess.Popen(["Hyprland"], cwd=self.base, env=compositor_env(env, self.base), start_new_session=True,
                                           stdout=(self.logs / "hyprland.log").open("w"), stderr=subprocess.STDOUT)
        self.socket = wait_for(lambda: next((p.name for p in self.runtime.glob("wayland-*[0-9]")), None),
                               "socket del Hyprland anidado")
        wait_for(lambda: (self.runtime / "hypr").is_dir() and any((self.runtime / "hypr").iterdir())
                 and self.monitors(), "IPC del Hyprland anidado")
        for _ in range(outputs - 1):
            self.hyprctl("output", "create", "headless")
        wait_for(lambda: len(self.monitors()) == outputs, f"{outputs} salidas")
        self.shell = subprocess.Popen(["qs", "-p", str(self.shell_dir)], env=self.env(), start_new_session=True,
                                      stdout=(self.logs / "qs.log").open("w"), stderr=subprocess.STDOUT)
        wait_for(lambda: self.ipc("drawers", "list").returncode == 0 and self.launcher_layers(), "IPC de Cortetsu",
                 timeout=60)
        self.input = subprocess.Popen([str(self.vinput_bin)], env=self.env(), text=True, start_new_session=True,
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        assert self.input.stdout.readline().strip() == "ready", "vinput no arrancó"
        time.sleep(1.0)

    def stop(self) -> None:
        for process in (self.client, self.input, self.shell, self.compositor, self.bus):
            if process and process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
        self.sweep()

    def sweep(self) -> list[int]:
        """Kill anything still running with this test's runtime directory.

        The shell's helpers (dbus-monitor, nmcli monitor, systemd-inhibit
        holding a real logind delay lock) outlive it when it is not in a
        cgroup; detached ones leave the process group. Matching on the
        private XDG_RUNTIME_DIR can only ever hit this test's processes.
        """
        marker = f"XDG_RUNTIME_DIR={self.runtime}".encode()
        killed = []
        for _ in range(3):
            found = []
            for entry in Path("/proc").iterdir():
                if not entry.name.isdigit() or int(entry.name) == os.getpid():
                    continue
                try:
                    if marker in (entry / "environ").read_bytes().split(b"\0"):
                        found.append(int(entry.name))
                except OSError:
                    continue
            if not found:
                break
            for pid in found:
                try:
                    os.kill(pid, signal.SIGKILL)
                    killed.append(pid)
                except ProcessLookupError:
                    pass
            time.sleep(0.3)
        return killed

    def start_client(self) -> Path:
        """A terminal whose stdin lands in a file: proves where keys go."""
        sink = self.base / "client-keys.txt"
        sink.touch()
        self.client = subprocess.Popen(
            ["kitty", "--config", "NONE", "--class", "cortetsu-probe", "sh", "-c", f"stty raw -echo; cat > {sink}"],
            env=self.env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        client = wait_for(lambda: next((c for c in self.hjson("clients") or [] if c.get("class") == "cortetsu-probe"), None),
                          "ventana cliente", timeout=20)
        time.sleep(0.8)
        self.click(client["at"][0] + client["size"][0] // 2, client["at"][1] + client["size"][1] // 2)
        wait_for(lambda: (self.hjson("activewindow") or {}).get("class") == "cortetsu-probe", "foco del cliente", timeout=5)
        return sink

    # queries -----------------------------------------------------------
    def hyprctl(self, *args: str) -> str:
        return subprocess.run([HYPRCTL, *args], text=True, capture_output=True, env=self.env(), timeout=10).stdout

    def hjson(self, *args: str):
        try:
            return json.loads(self.hyprctl(*args, "-j") or "null")
        except ValueError:
            return None

    def monitors(self) -> list[dict]:
        return self.hjson("monitors") or []

    def ipc(self, target: str, method: str, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["qs", "ipc", "-p", str(self.shell_dir), "call", target, method, *args],
                              text=True, capture_output=True, env=self.env(), timeout=10)

    def headless(self) -> list[str]:
        """Outputs with their own frame clock.

        WAYLAND-1 is a window inside the desktop session: it only gets frames
        when the parent compositor paints it, so a client commit there can
        wait seconds (seen as a launcher that changed state but not its
        surface). Scenarios run on headless outputs only.
        """
        return [m["name"] for m in self.monitors() if m["name"].startswith("HEADLESS-")]

    def focused_monitor(self) -> str:
        return next((m["name"] for m in self.monitors() if m["focused"]), "")

    def focus_monitor(self, name: str) -> None:
        """Move the pointer to a monitor's centre, as a user would."""
        monitor = next(m for m in self.monitors() if m["name"] == name)
        self.move(monitor["x"] + monitor["width"] // 2, monitor["y"] + monitor["height"] // 2)
        # Pointer motion alone does not move monitor focus while a layer
        # holds the keyboard after typing; the dispatcher does, like a
        # focus-monitor keybind would.
        self.hyprctl("dispatch", f'hl.dsp.focus({{ monitor = "{name}" }})')
        try:
            wait_for(lambda: self.focused_monitor() == name, f"foco en {name}", timeout=5)
        except AssertionError as exc:
            raise AssertionError(f"{exc}; focused={self.focused_monitor()} cursor={self.hyprctl('cursorpos').strip()} "
                                 f"layers={[(l['monitor'], l['namespace']) for l in self.launcher_layers()]}") from None
        time.sleep(0.2)

    def launcher_states(self) -> dict[str, bool]:
        """Launcher flag of every screen, read without moving focus."""
        result = self.ipc("drawers", "launcherScreens")
        assert result.returncode == 0, result.stderr
        open_screens = set(result.stdout.split())
        return {m["name"]: m["name"] in open_screens for m in self.monitors()}

    def launcher_open(self) -> bool:
        """Launcher state of the focused monitor, read through the shell's own IPC."""
        return self.ipc("drawers", "isOpen", "launcher").stdout.strip() == "1"

    def launcher_layers(self) -> list[dict]:
        layers = []
        for monitor, data in (self.hjson("layers") or {}).items():
            for level in data.get("levels", {}).values():
                layers += [dict(layer, monitor=monitor) for layer in level if layer.get("namespace") == "cortetsu-launcher"]
        return layers

    def keyboard_layer(self) -> str:
        """Namespace of the layer surface holding keyboard focus, if any."""
        return (self.hjson("activelayer") or {}).get("namespace", "") if self.hjson("activelayer") else ""

    # input -------------------------------------------------------------
    def send(self, command: str) -> None:
        self.input.stdin.write(command + "\n")
        self.input.stdin.flush()
        assert self.input.stdout.readline().strip() == "ok", command

    def tap(self, key: int, hold: float = 0.03) -> None:
        self.send(f"key {key} 1")
        time.sleep(hold)
        self.send(f"key {key} 0")

    def chord(self, modifier: int, key: int) -> None:
        self.send(f"key {modifier} 1")
        time.sleep(0.03)
        self.tap(key)
        time.sleep(0.03)
        self.send(f"key {modifier} 0")

    def move(self, x: int, y: int) -> None:
        """Absolute position in the layout of all monitors."""
        width = max(m["x"] + m["width"] for m in self.monitors())
        height = max(m["y"] + m["height"] for m in self.monitors())
        self.send(f"move {x} {y} {width} {height}")

    def click(self, x: int, y: int) -> None:
        self.move(x, y)
        time.sleep(0.05)
        self.send(f"button {BTN_LEFT} 1")
        time.sleep(0.03)
        self.send(f"button {BTN_LEFT} 0")
