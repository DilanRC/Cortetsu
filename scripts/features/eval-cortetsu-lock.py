from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
pam = (ROOT / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")

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
assert 'phase: root.markPhase' in surface
assert 'Qt.callLater(() => keyboardFocus.forceActiveFocus())' in surface
assert 'function onSecureChanged(): void' in surface
assert 'root.lock.secure && !activeFocus' in surface
assert 'property bool authenticationAccepted' in surface
assert ' ? "Ascended"' in surface and ' ? "Awakening"' in surface and ': "Human"' in surface
assert 'function onAuthenticationSucceeded(): void' in surface
assert 'pam.releaseAfterSuccess()' in surface
assert 'interval: CortetsuDesign.motionStandardMs' in surface
assert 'signal authenticationSucceeded' in pam
assert 'root.successPending = true' in pam
assert 'root.authenticationSucceeded()' in pam
assert 'function releaseAfterSuccess(): void' in pam
assert 'if (passwd.active || successPending)' in pam
assert 'return root.lock.unlock()' not in pam
lock = (ROOT / "cortetsu/modules/lock/Lock.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
assert "readonly property bool lockReady" in lock
assert "function requestLock(): void" in lock
assert "SessionHost { lockController: lock }" in shell

print("PASS: Lock visual preserves secure focus while exposing live identity, keyboard, power and network context")
