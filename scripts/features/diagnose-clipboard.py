#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import time
from pathlib import Path

HOME = Path.home()
UID = os.getuid()
LIVE = Path(os.environ.get("CORTETSU_LIVE_ROOT", str(Path.home() / ".config/quickshell/cortetsu/current")))
REPO = Path(__file__).resolve().parents[2]


def newest_log() -> Path | None:
    root = Path(f"/run/user/{UID}/quickshell/by-id")
    logs = list(root.glob("*/log.qslog"))
    if not logs:
        return None
    return max(logs, key=lambda p: p.stat().st_mtime_ns)


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, check=False)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def print_section(title: str) -> None:
    print(f"\n===== {title} =====")


log = newest_log()
if log is None:
    raise SystemExit("ERROR: no encontré log.qslog de Quickshell")

print(f"Log: {log}")
start = log.stat().st_size

# Ensure a deterministic initial state, then reproduce the bug without keyboard input.
run("qs", "-p", str(LIVE), "ipc", "call", "clipboard", "close")
time.sleep(0.4)

open_result = run("qs", "-p", str(LIVE), "ipc", "call", "clipboard", "open")
if open_result.returncode != 0:
    print(open_result.stdout, end="")
    print(open_result.stderr, end="")
    raise SystemExit("ERROR: no pude abrir clipboard por IPC")

time.sleep(3.0)
is_open = run("qs", "-p", str(LIVE), "ipc", "call", "clipboard", "isOpen")
run("qs", "-p", str(LIVE), "ipc", "call", "clipboard", "close")
time.sleep(0.5)

with log.open("rb") as f:
    f.seek(start)
    appended = f.read().decode("utf-8", errors="replace")

print_section("IPC")
print("isOpen mientras estaba abierto:", is_open.stdout.strip() or "<sin salida>")
if is_open.stderr.strip():
    print("stderr:", is_open.stderr.strip())

print_section("LOG NUEVO COMPLETO")
print(appended.rstrip() or "<sin líneas nuevas>")

print_section("ERRORES / WARNINGS RELEVANTES")
pattern = re.compile(
    r"clipboard|qml|error|warning|warn|failed|unable|invalid|cannot|referenceerror|typeerror|binding|loop|undefined",
    re.IGNORECASE,
)
matched = [line for line in appended.splitlines() if pattern.search(line)]
print("\n".join(matched) if matched else "<ninguno>")

print_section("CONTENTWINDOW")
content_window = LIVE / "modules/drawers/ContentWindow.qml"
for lineno, line in enumerate(content_window.read_text(encoding="utf-8").splitlines(), 1):
    if re.search(r"surfaceColour|mask:|clipboard|keyboardFocus|opacity:", line):
        print(f"{lineno}: {line}")

print_section("LIVE VS REPO HASHES")
files = [
    "modules/clipboard/Content.qml",
    "modules/clipboard/ClipboardItem.qml",
    "modules/clipboard/Wrapper.qml",
]
for rel in files:
    live_path = LIVE / rel
    repo_path = REPO / "cortetsu" / rel
    live_hash = sha256(live_path) if live_path.exists() else "MISSING"
    repo_hash = sha256(repo_path) if repo_path.exists() else "MISSING"
    state = "MATCH" if live_hash == repo_hash else "DIFF"
    print(f"{state:5}  {rel}")
    print(f"       live {live_hash}")
    print(f"       repo {repo_hash}")

print_section("SCHEME")
scheme_candidates = [
    HOME / ".local/state/cortetsu/scheme.json",
    HOME / ".local/share/cortetsu/scheme.json",
]
found = False
for scheme in scheme_candidates:
    if scheme.exists():
        found = True
        print(f"Path: {scheme}")
        text = scheme.read_text(encoding="utf-8", errors="replace")
        for key in [
            '"name"',
            '"mode"',
            '"background"',
            '"surface"',
            '"surfaceContainer"',
            '"surfaceContainerHigh"',
            '"inverseSurface"',
            '"inverseOnSurface"',
            '"onSurface"',
            '"primaryFixedDim"',
        ]:
            for line in text.splitlines():
                if key in line:
                    print(line.strip())
                    break
if not found:
    print("<scheme.json no encontrado en rutas conocidas>")

print("\nDIAGNÓSTICO TERMINADO")
