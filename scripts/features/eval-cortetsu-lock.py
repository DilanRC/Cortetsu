from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")

assert "Qt.alpha(CortetsuDesign.colorSumi" in surface
assert "secure" not in surface.lower() or "password" in surface.lower()
assert "repeat(pam.buffer.length)" in surface
assert "UPower.displayDevice" in surface and "CortetsuNetwork.active" in surface
assert "Icons.getBatteryIcon" in surface and "batteryCharging" in surface
assert 'command: ["hyprctl", "-j", "devices"]' in surface
assert "active_keymap" in surface and "capsLock" in surface and "numLock" in surface
assert 'Quickshell.env("USER")' in surface
assert "CortetsuDesign.colorWarning" in surface
assert "Keyboard layout · Enter to authenticate" not in surface

print("PASS: Lock visual preserves secure focus while exposing live identity, keyboard, power and network context")
