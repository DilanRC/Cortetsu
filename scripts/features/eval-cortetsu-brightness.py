from pathlib import Path

source = Path(__file__).resolve().parents[2] / "cortetsu/services/Brightness.qml"
text = source.read_text(encoding="utf-8")
assert '"brightnessctl", "-l", "-m"' in text
assert 'item.split(",")[1] === "backlight"' in text
assert "raw / root.backlightMax" in text
assert "brightness = -1" in text
assert "writeProcess" in text and "readProcess.running" in text
print("PASS: brightness eval requires discovered backlight, normalized readback, and unsupported state")
