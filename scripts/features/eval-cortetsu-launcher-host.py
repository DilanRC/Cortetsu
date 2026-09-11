from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/LauncherHost.qml").read_text(encoding="utf-8")
assert "CortetsuShellState.forScreen(modelData)" in host
assert "CortetsuShellState.forActive()" not in host
assert "launcher.focusSearch()" in host
assert "Escape" in host
assert "anchors.bottomMargin" in host
print("PASS: launcher host owns monitor-local focus, escape, and bottom-centered geometry")
