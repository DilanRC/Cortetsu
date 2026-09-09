from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
lock = (ROOT / "cortetsu/modules/lock/Lock.qml").read_text(encoding="utf-8")
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
pam = (ROOT / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")

for marker in ("WlSessionLock", "Pam", 'target: "lock"', "sessionLock.unlock"):
    assert marker in lock, marker

for marker in (
    "WlSessionLockSurface",
    "pam.handleKey",
    "Password",
    "Authentication failed",
    "ScreencopyView",
    "CortetsuEvolvingMark",
    'phase: root.markPhase',
    "property bool authenticationAccepted",
    "interactionActive",
    ' ? "Ascended"',
    ' ? "Awakening"',
    ': "Human"',
    "onAuthenticationSucceeded",
    "unlockTransition",
    "pam.releaseAfterSuccess",
    "interval: CortetsuDesign.motionStandardMs",
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
mark_start = surface.index("readonly property string markPhase")
assert "pam.state" not in surface[mark_start:mark_start + 320]
assert 'text: qsTr("CAPS")' in surface
assert 'text: qsTr("Enter to authenticate")' in surface
assert "Lock { id: lock }" in shell
for marker in ("signal authenticationSucceeded", "property bool successPending", "root.authenticationSucceeded()", "function releaseAfterSuccess", "root.lock.unlock()"):
    assert marker in pam, marker
assert "if (passwd.active || successPending)" in pam

print("PASS: Lock keeps PAM/session-lock semantics and surfaces live Cortetsu user, keyboard, power and network context")
