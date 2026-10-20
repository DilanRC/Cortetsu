"""launcher_harness.Session with every host-touching command stubbed (F0).

Session already isolates HOME, XDG_*, XDG_RUNTIME_DIR, D-Bus, input and the
GPU, and keeps ~/.local/bin off PATH. Its PATH still reaches /usr/bin, where
the shell's services find systemctl, nmcli, brightnessctl, busctl... Here
those names, and every cortetsu-* helper name, resolve to a stub that logs
argv and prints {}: the run is read-only for the host and the log lists what
the shell would have called. Run it under ws2_run.py so the nested window is
born on WS 2.
"""
from __future__ import annotations

import os
from pathlib import Path
import signal
import subprocess
import time

from launcher_harness import Session, wait_for

HOST_STUBS = ("systemctl", "busctl", "nmcli", "brightnessctl", "powerprofilesctl", "systemd-inhibit",
              "notify-send", "wl-copy", "loginctl", "gpu-screen-recorder", "secret-tool", "ydotool",
              "bluetoothctl", "wpctl", "pactl", "playerctl", "upower", "hyprsunset")


class F0Session(Session):
    def write_fixtures(self) -> None:
        super().write_fixtures()
        bin_dir = self.base / "bin"
        self.stub_calls = self.base / "stub-calls.log"
        self.stub_calls.touch()
        names = set(HOST_STUBS) | {p.name for p in (Path.home() / ".local/bin").glob("cortetsu*")}
        for name in sorted(names - {"cortetsu-launch-persistent"}):
            stub = bin_dir / name
            stub.write_text(f'#!/bin/sh\nprintf "%s %s\\n" "{name}" "$*" >> "{self.stub_calls}"\necho "{{}}"\n')
            stub.chmod(0o755)

    def start_shell(self) -> dict:
        """(Re)start qs. ms from spawn to "Configuration Loaded" in its log, and
        to the shell answering `drawers list` with its layers mapped."""
        log = self.logs / "qs.log"
        offset = log.stat().st_size if log.exists() else 0
        started = time.perf_counter()
        self.shell = subprocess.Popen(["qs", "-p", str(self.shell_dir)], env=self.env(), start_new_session=True,
                                      stdout=log.open("a"), stderr=subprocess.STDOUT)

        def loaded() -> bool:
            with log.open(errors="replace") as handle:
                handle.seek(offset)
                return "Configuration Loaded" in handle.read()

        wait_for(loaded, "Configuration Loaded", timeout=60)
        loaded_ms = (time.perf_counter() - started) * 1000
        wait_for(lambda: self.ipc("drawers", "list").returncode == 0 and self.launcher_layers(), "IPC de Cortetsu",
                 timeout=60)
        return {"loaded_ms": loaded_ms, "ready_ms": (time.perf_counter() - started) * 1000}

    def stop_shell(self) -> None:
        if self.shell and self.shell.poll() is None:
            os.killpg(self.shell.pid, signal.SIGTERM)
            try:
                self.shell.wait(10)
            except subprocess.TimeoutExpired:
                os.killpg(self.shell.pid, signal.SIGKILL)
                self.shell.wait()
