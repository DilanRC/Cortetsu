#!/usr/bin/env python3
"""Record which workspace and monitor are active in a Hyprland session (read-only).

    python3 -I ws_watch.py OUT.jsonl [--signature SIG] [--runtime DIR]

Writes one JSON line per socket2 event (workspace, focus, window and urgency
events) and one `poll` line every 0.5 s with the active workspace and focused
monitor, both stamped with CLOCK_MONOTONIC and wall time. Runs until SIGTERM/INT.
Defaults to the session in HYPRLAND_INSTANCE_SIGNATURE / XDG_RUNTIME_DIR.
"""
import argparse, json, os, signal, socket, subprocess, sys, threading, time

KEEP = ("workspace", "focusedmon", "activewindow", "openwindow", "closewindow", "urgent", "movewindow", "activespecial")

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--signature", default=os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))
ap.add_argument("--runtime", default=os.environ.get("XDG_RUNTIME_DIR"))
a = ap.parse_args()
env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=a.signature, XDG_RUNTIME_DIR=a.runtime)
out = open(a.out, "a", buffering=1)
lock = threading.Lock()
stop = threading.Event()


def emit(kind, **data):
    with lock:
        out.write(json.dumps({"t": round(time.monotonic(), 3), "wall": round(time.time(), 3), "kind": kind, **data}) + "\n")


def state():
    q = lambda what: json.loads(subprocess.run(["/usr/bin/hyprctl", what, "-j"], env=env, capture_output=True, text=True).stdout or "null")
    ws, mons = q("activeworkspace"), q("monitors") or []
    focused = next((m["name"] for m in mons if m.get("focused")), None)
    return {"ws": ws and ws.get("id"), "monitor": focused, "monitors": {m["name"]: m["activeWorkspace"]["id"] for m in mons}}


def events():
    s = socket.socket(socket.AF_UNIX)
    s.connect(f"{a.runtime}/hypr/{a.signature}/.socket2.sock")
    buf = b""
    while not stop.is_set():
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
        *lines, buf = buf.split(b"\n")
        for line in lines:
            name, _, arg = line.decode(errors="replace").partition(">>")
            if name.startswith(KEEP):
                # Window titles are the user's data (terminal, browser): keep address, workspace and class only.
                if name in ("activewindow", "openwindow"):
                    arg = ",".join(arg.split(",")[:1 if name == "activewindow" else 3])
                emit("event", name=name, arg=arg)


signal.signal(signal.SIGTERM, lambda *_: stop.set())
signal.signal(signal.SIGINT, lambda *_: stop.set())
threading.Thread(target=events, daemon=True).start()
emit("start", **state())
last = None
while not stop.wait(0.5):
    now = state()
    if now != last:
        emit("poll", **now)
        last = now
emit("stop", **state())
