import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
hypr = (modules / "CortetsuHypr.qml").read_text(encoding="utf-8")
screens = (modules / "CortetsuScreens.qml").read_text(encoding="utf-8")
service = (repo / "cortetsu/services/Hypr.qml").read_text(encoding="utf-8")

assert "pragma Singleton" in hypr and "pragma Singleton" in screens
for marker in ("toplevels", "workspaces", "monitors", "activeToplevel", "focusedWorkspace", "focusedMonitor", "activeWsId", "usingLua", "dispatch", "isTaskbarToplevel"):
    assert marker in hypr, marker
assert "readonly property var screens" in screens
assert "function monitorFor(screen)" in screens
assert "CortetsuHypr.monitorFor(screen)" in screens
assert "import qs.services" not in hypr + screens
assert "import Quickshell.Hyprland" in hypr
assert "Hyprland.dispatch(request)" in hypr
assert "Hyprland.monitorFor(screen)" not in hypr
assert "Hyprland.monitors.values.find(monitor => monitor.name === name)" in hypr
assert "window.mapped === false" in hypr
assert "Number.isFinite(Number(window.pid))" in hypr
assert "Quickshell.screens" in screens
assert "CortetsuHypr" in service
assert "import Caelestia" not in service
assert "import Caelestia.Config" not in service
assert "import Caelestia.Services" not in service
assert "Hyprland.dispatch(message)" in service

for path in modules.rglob("*.qml"):
    if path.name in {"CortetsuHypr.qml", "CortetsuScreens.qml"}:
        continue
    text = path.read_text(encoding="utf-8")
    assert not re.search(r"(?<!Cortetsu)Screens\.screens", text), path
    assert not re.search(r"(?<!Cortetsu)Hypr\.toplevels", text), path
    assert not re.search(r"(?<!Cortetsu)Hypr\.dispatch", text), path
    if "CortetsuHypr" in text or "CortetsuScreens" in text:
        if path.parent != modules:
            assert 'import ".."' in text, path

print("PASS: Cortetsu Hyprland and screen adapters own backend access")
