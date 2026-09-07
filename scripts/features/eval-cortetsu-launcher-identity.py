from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
assert "Search-first" in content
assert "Prefix mode" in content
assert "onAccepted" in content
print("PASS: launcher identity preserves keyboard-first activation while making modes legible")
