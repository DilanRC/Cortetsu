from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
assert "Layout.preferredWidth: 1.65" in dash
assert "Desktop context" in dash
assert "No active media" in dash
assert "Live context" in dash
assert "Weather" in dash
print("PASS: Dashboard establishes dominant context, secondary media, and restrained system hierarchy")
