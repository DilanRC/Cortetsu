#!/usr/bin/env python3
"""Real-tool check that a copied Wi-Fi password never reaches clipse's history.

Runs a nested Hyprland with its own runtime directory, a clipse watcher with an
isolated HOME and the exact wl-copy command Settings uses. The live clipboard
and the real history are never touched. Needs a Wayland session to nest in.

    python3 scripts/integration/test-clipboard-sensitive-history.py
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("cortetsu_startup", str(REPO / "cortetsu/bin/cortetsu-startup"))
spec = importlib.util.spec_from_loader("cortetsu_startup", loader)
startup = importlib.util.module_from_spec(spec)
loader.exec_module(startup)
COPY = next(entry["command"] for entry in startup.CORTETSU_STARTUP
            if entry["id"] == "cortetsu:network-password-clipboard")

parent = os.environ.get("WAYLAND_DISPLAY")
assert parent, "needs a Wayland session to nest Hyprland in"
for tool in ("Hyprland", "wl-copy", "wl-paste", "clipse"):
    assert shutil.which(tool), f"{tool} is not installed"
parent_socket = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)

with tempfile.TemporaryDirectory(prefix="cortetsu-clip-") as temporary:
    root = Path(temporary)
    runtime = root / "run"
    runtime.mkdir(mode=0o700)
    (root / "cfg/hypr").mkdir(parents=True)
    (root / "cfg/hypr/hyprland.lua").write_text("hl.config({ misc = { disable_hyprland_logo = true } })\n")
    base = {"HOME": str(root), "PATH": os.environ["PATH"], "XDG_RUNTIME_DIR": str(runtime),
            "XDG_CONFIG_HOME": str(root / "cfg")}
    compositor = subprocess.Popen(["Hyprland"], cwd=root, env=dict(base, WAYLAND_DISPLAY=parent_socket),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    watcher = None
    try:
        deadline = time.time() + 20
        while not list(runtime.glob("wayland-*[0-9]")) and time.time() < deadline:
            time.sleep(0.2)
        sockets = sorted(path.name for path in runtime.glob("wayland-*[0-9]"))
        assert sockets, "nested Hyprland did not start"
        nested = dict(base, WAYLAND_DISPLAY=sockets[0])
        # Same pipeline `clipse -listen` starts for text.
        watcher = subprocess.Popen(["wl-paste", "--type", "text", "--watch", "clipse", "--wl-store"],
                                   env=nested, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)
        history = root / "cfg/clipse/clipboard_history.json"

        subprocess.run(["wl-copy"], input="cortetsu-plain-marker", text=True, env=nested, check=True)
        time.sleep(1.5)
        assert history.exists() and "cortetsu-plain-marker" in history.read_text(), \
            "control failed: the watcher did not store a normal copy"

        secret = "cortetsu-synthetic-secret-4f2c"
        offer = subprocess.Popen(COPY, stdin=subprocess.PIPE, text=True, env=nested,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        offer.stdin.write(secret)
        offer.stdin.close()
        time.sleep(1.5)
        pasted = subprocess.run(["wl-paste", "--no-newline"], text=True, capture_output=True, env=nested).stdout
        assert pasted == secret, "the sensitive offer was not pasteable"
        assert secret not in history.read_text(), "sensitive copy reached clipse's history"

        offer.terminate()
        offer.wait(timeout=5)
        time.sleep(0.5)
        after = subprocess.run(["wl-paste", "--no-newline"], text=True, capture_output=True, env=nested)
        assert secret not in after.stdout, "ending the offer left the secret on the clipboard"
        assert secret not in history.read_text(), "sensitive copy reached clipse's history after expiry"
    finally:
        if watcher:
            watcher.terminate()
        compositor.terminate()
        try:
            compositor.wait(timeout=10)
        except subprocess.TimeoutExpired:
            compositor.kill()
print("PASS: sensitive wl-copy is pasteable, skipped by clipse and gone after the offer ends")
