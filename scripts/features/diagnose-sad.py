#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LIVE = Path(os.environ.get("CORTETSU_LIVE_ROOT", str(Path.home() / ".config/quickshell/cortetsu/current")))
UID = os.getuid()
errors: list[str] = []
warnings: list[str] = []
rows: list[dict] = []

WIRING = {
    "hardware": {"controller": "HardwareController", "flag": "hardware", "ipc": "hardware"},
    "display": {"controller": "DisplayController", "flag": "displayManager", "ipc": "display"},
    "wallpaper": {"controller": "WallpaperController", "flag": "wallpaperManager", "ipc": "wallpapermanager"},
}

RETIRED_LIVE = [
    "modules/GamingController.qml",
    "modules/gaming",
    "modules/UpdaterController.qml",
    "modules/updater",
]
RETIRED_HELPERS = [
    "cortetsu-gaming-probe",
    "cortetsu-gaming-profile",
    "cortetsu-upstream-audit",
    "cortetsu-updater",
    "cortetsu-updater-commit-base",
]


def read(rel: str) -> str | None:
    path = LIVE / rel
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def check_wiring() -> dict[str, bool]:
    shell = read("shell.qml")
    screen = read("components/ScreenState.qml")
    panels = read("modules/drawers/Panels.qml")
    wired: dict[str, bool] = {}
    for feature, spec in WIRING.items():
        missing = []
        if shell is None or f"{spec['controller']} {{}}" not in shell:
            missing.append("shell.qml controller")
        if screen is None or f"property bool {spec['flag']}" not in screen:
            missing.append("ScreenState.qml flag")
        if panels is None or f"id: {spec['flag']}" not in panels:
            missing.append("Panels.qml Wrapper")
        wired[feature] = not missing
        if missing:
            errors.append(
                f"{feature}: not wired into live shell ({', '.join(missing)})"
            )
    return wired


def check_retired() -> None:
    shell = read("shell.qml") or ""
    screen = read("components/ScreenState.qml") or ""
    panels = read("modules/drawers/Panels.qml") or ""
    content = read("modules/drawers/ContentWindow.qml") or ""
    usercfg = Path.home() / ".config/hypr/hypr-user.lua"
    try:
        user = usercfg.read_text(encoding="utf-8")
    except OSError:
        user = ""

    marker_sets = {
        "shell.qml": ("GamingController", "UpdaterController"),
        "ScreenState.qml": ("gamingCenter", "updaterCenter"),
        "Panels.qml": (
            "qs.modules.gaming", "qs.modules.updater", "gamingCenter", "updaterCenter"
        ),
        "ContentWindow.qml": ("gamingCenter", "updaterCenter"),
        "hypr-user.lua": ("cortetsu:gamingcenter", "cortetsu:updatercenter"),
    }
    texts = {
        "shell.qml": shell,
        "ScreenState.qml": screen,
        "Panels.qml": panels,
        "ContentWindow.qml": content,
        "hypr-user.lua": user,
    }
    for label, markers in marker_sets.items():
        found = [marker for marker in markers if marker in texts[label]]
        if found:
            errors.append(
                f"retired center wiring remains in {label}: {', '.join(found)}"
            )

    for rel in RETIRED_LIVE:
        if (LIVE / rel).exists():
            errors.append(f"retired live artifact remains: {LIVE / rel}")

    for name in RETIRED_HELPERS:
        path = Path.home() / ".local/bin" / name
        if path.exists():
            errors.append(f"retired helper remains: {path}")


def sha(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return ""


def cmd(args: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            args, text=True, capture_output=True, timeout=timeout, check=False
        )
    except Exception:
        return None


def check_file(rel: str) -> None:
    src = REPO / "cortetsu/modules" / rel
    live = LIVE / rel
    same = src.is_file() and live.is_file() and sha(src) == sha(live)
    rows.append({"path": rel, "repo": src.is_file(), "live": live.is_file(), "match": same})
    if not same:
        warnings.append(f"live mismatch: {rel}")


def json_helper(name: str, args: list[str] | None = None) -> None:
    path = Path.home() / ".local/bin" / name
    if not path.is_file():
        warnings.append(f"missing installed helper: {name}")
        return
    cp = cmd([str(path)] + (args or []), 25)
    if not cp or cp.returncode != 0:
        errors.append(f"{name}: failed")
        return
    try:
        json.loads(cp.stdout)
    except Exception as exc:
        errors.append(f"{name}: invalid JSON: {exc}")


def main() -> None:
    for rel in [
        "modules/HardwareController.qml",
        "modules/hardware/Wrapper.qml",
        "modules/hardware/Content.qml",
        "modules/DisplayController.qml",
        "modules/display/Wrapper.qml",
        "modules/settings/display/DisplayPage.qml",
        "modules/settings/display/DisplayModel.qml",
        "modules/settings/display/DisplayTransaction.qml",
        "modules/settings/display/DisplayPresetStore.qml",
        "modules/settings/display/DisplayArrangement.qml",
        "modules/WallpaperController.qml",
        "modules/OverlayPolicy.js",
        "modules/wallpaper/Wrapper.qml",
        "modules/wallpaper/Content.qml",
        "modules/wallpaper/OrbitModel.js",
    ]:
        check_file(rel)

    json_helper("cortetsu-hardware-probe")
    json_helper("cortetsu-hardware-power")
    json_helper("cortetsu-display-probe")
    json_helper("cortetsu-display-transaction", ["status"])
    json_helper("cortetsu-display-persist", ["status"])
    json_helper("cortetsu-display-presets", ["list"])
    json_helper("cortetsu-display-workspaces", ["status"])

    wired = check_wiring()
    check_retired()

    ipc: dict[str, dict] = {}
    for feature, spec in WIRING.items():
        target = spec["ipc"]
        cp = cmd(["qs", "-p", str(LIVE), "ipc", "call", target, "isOpen"], 8)
        out = cp.stdout.strip() if cp else ""
        ok = bool(cp and cp.returncode == 0 and out in ("true", "false"))
        ipc[feature] = {"target": target, "ok": ok, "output": out}
        if not ok:
            errors.append(f"IPC target not responding: {target} -> {out!r}")

    retired_ipc: dict[str, str] = {}
    for target in ["gaming", "updater"]:
        cp = cmd(["qs", "-p", str(LIVE), "ipc", "call", target, "isOpen"], 8)
        out = cp.stdout.strip() if cp else ""
        retired_ipc[target] = out
        if out in ("true", "false"):
            errors.append(f"retired IPC target still active: {target} -> {out!r}")

    auto: dict[str, str] = {}
    for action in ["is-enabled", "is-active"]:
        cp = cmd(["systemctl", "--user", action, "cortetsu-power-auto.service"], 8)
        auto[action] = cp.stdout.strip() if cp else "unknown"

    persistent: list[str] = []
    retired_processes: list[str] = []
    cp = cmd(["ps", "-eo", "pid=,args="], 10)
    if cp:
        for line in cp.stdout.splitlines():
            if re.search(
                r"cortetsu-(hardware-(probe|power)|display-(probe|plan|persist|presets|workspaces))",
                line,
            ) and "diagnose-sad.py" not in line:
                persistent.append(line.strip())
            if re.search(
                r"cortetsu-(gaming-(probe|profile)|upstream-audit|updater(?:-commit-base)?)",
                line,
            ) and "diagnose-sad.py" not in line:
                retired_processes.append(line.strip())

    if persistent:
        warnings.extend([f"helper still running: {line}" for line in persistent[:12]])
    if retired_processes:
        errors.extend([f"retired helper still running: {line}" for line in retired_processes[:12]])

    qml_errors: list[str] = []
    root = Path(f"/run/user/{UID}/quickshell/by-id")
    logs = (
        sorted(
            root.glob("*/log.qslog"),
            key=lambda path: path.stat().st_mtime if path.exists() else 0,
            reverse=True,
        )
        if root.exists()
        else []
    )
    if logs:
        cp = cmd(["strings", str(logs[0])], 15)
        if cp:
            for line in cp.stdout.splitlines():
                if re.search(
                    r"@.*\.qml\[[0-9]+:-1\]: (ReferenceError|TypeError|Error:)", line
                ) and not re.search(
                    r"Received event|windowtitle|activewindow|got toplevel", line, re.I
                ):
                    qml_errors.append(line)
                elif re.search(
                    r"(Type .* unavailable|Binding loop detected|Cannot assign)", line
                ) and ("@" in line or ".qml" in line):
                    qml_errors.append(line)
    if qml_errors:
        errors.extend([f"QML: {item}" for item in qml_errors[:20]])

    print("===== SAD LIVE DIAGNOSTICS =====")
    for row in rows:
        print(("MATCH " if row["match"] else "MISS  ") + row["path"])
    print("\nWiring:", json.dumps(wired, ensure_ascii=False))
    print("IPC:", json.dumps(ipc, ensure_ascii=False))
    print("Retired IPC:", json.dumps(retired_ipc, ensure_ascii=False))
    print("Power Auto:", json.dumps(auto, ensure_ascii=False))
    print("Unexpected persistent helpers:", len(persistent))
    print("Retired helper processes:", len(retired_processes))
    print("QML log:", str(logs[0]) if logs else "none")
    print("QML errors:", len(qml_errors))

    if warnings:
        print("\nWARNINGS")
        for item in warnings:
            print("-", item)
    if errors:
        print("\nERRORS")
        for item in errors:
            print("-", item)
        print("\nSAD DIAGNOSTIC: FAIL")
        raise SystemExit(1)

    print("\nSAD DIAGNOSTIC: OK" if not warnings else "\nSAD DIAGNOSTIC: OK_WITH_WARNINGS")


if __name__ == "__main__":
    main()
