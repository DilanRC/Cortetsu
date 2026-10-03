from pathlib import Path

source = Path(__file__).resolve().parents[2] / "cortetsu/services/Brightness.qml"
text = source.read_text(encoding="utf-8")
assert "Caelestia" not in text
for contract in ("component Monitor", "getMonitorForScreen", "setFor", 'target: "brightness"',
                 'command: ["brightnessctl", "-l", "-m"]', 'item.split(",")[1] === "backlight"',
                 "backlightMax", '"/sys/class/backlight/" + root.backlightDevice + "/max_brightness"', "maxProcess",
                 "raw / root.backlightMax", "writeProcess", "pendingBrightness",
                 "onExited: monitor.readProcess.running", "if (!supported)", "function status()"):
    assert contract in text
assert "Number(text.trim()) / 100" not in text
assert '"*" + monitor.monitorName + "*"' not in text
print("PASS: Cortetsu owns the Brightness service contract")
