from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
lock = (ROOT / "cortetsu/modules/lock/Lock.qml").read_text(encoding="utf-8")
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")

for marker in ("WlSessionLock", "Pam", 'target: "lock"', "sessionLock.unlock"):
    assert marker in lock, marker

for marker in (
    "WlSessionLockSurface",
    "pam.handleKey",
    "Password",
    "Authentication failed",
    "ScreencopyView",
    "cortetsu-mark.svg",
    'command: ["hyprctl", "-j", "devices"]',
    "active_keymap",
    "capsLock",
    "numLock",
    'Quickshell.env("USER")',
    "CortetsuNetwork.activeEthernet",
    "UPower.displayDevice",
    "Icons.getBatteryIcon",
    "batteryCharging",
):
    assert marker in surface, marker

assert "Keyboard layout · Enter to authenticate" not in surface
assert "root.keyboardLayout" in surface
assert "root.userLabel" in surface
assert 'text: qsTr("CAPS")' in surface
assert 'text: qsTr("Enter to authenticate")' in surface
assert "Lock { id: lock }" in shell

print("PASS: Lock keeps PAM/session-lock semantics and surfaces live Cortetsu user, keyboard, power and network context")
