from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/LauncherHost.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
assert "CortetsuShellState.forScreen(modelData)" in host
assert "CortetsuShellState.forActive()" not in host
assert "launcher.focusSearch()" in host
assert "Escape" in host
assert "anchors.verticalCenter: parent.verticalCenter" in host
assert "dockOffset" not in host
launcher_block = panels[panels.index("Launcher.Wrapper"):panels.index("// Retained surfaces")]
assert "anchors.verticalCenter: parent.verticalCenter" in launcher_block
assert "anchors.bottom: parent.bottom" not in launcher_block
print("PASS: launcher host owns monitor-local focus, escape, and centered geometry")
