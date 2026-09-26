from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/LauncherHost.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
for marker in (
    'name: "launcher"',
    "Variants {",
    "model: CortetsuScreens.screens",
    "required property ShellScreen modelData",
    "CortetsuShellState.forScreen(modelData)",
    "screen: modelData",
    "WlrLayer.Overlay",
    "WlrKeyboardFocus.Exclusive",
    "panels: null",
):
    assert marker in host, marker
assert "CortetsuShellState.forActive()" not in host
assert "visible: false" in panels
assert "LauncherHost {}" in shell
print("PASS: launcher has a monitor-local first-party overlay host and no legacy panel visual consumer")
