from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
lock = (ROOT / "cortetsu/modules/lock/Lock.qml").read_text(encoding="utf-8")
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
pam = (ROOT / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")

for marker in ("WlSessionLock", "Pam", 'target: "lock"', "lockReady", "requestLock"):
    assert marker in lock, marker

for marker in (
    "WlSessionLockSurface",
    'import ".."',
    "pam.handleKey",
    "Contraseña",
    "La autenticación falló. Inténtalo de nuevo.",
    "ScreencopyView",
    "CortetsuEvolvingMark",
    'phase: root.markPhase',
    "property bool authenticationAccepted",
    "interactionActive",
    "Qt.callLater(() => keyboardFocus.forceActiveFocus())",
    "onSecureChanged",
    "onActiveFocusChanged",
    "root.lock.secure && !activeFocus",
    ' ? "Ascended"',
    ' ? "Awakening"',
    ': "Human"',
    "onAuthenticationSucceeded",
    "unlockTransition",
    "pam.releaseAfterSuccess",
    "if (pam.successPending)",
    "interval: CortetsuDesign.motionStandardMs",
    'command: ["hyprctl", "-j", "devices"]',
    "active_keymap",
    "capsLock",
    "numLock",
    'Quickshell.env("USER")',
    "CortetsuNetwork.activeEthernet",
    "CortetsuPower",
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
assert 'text: qsTr("Pulsa Enter para autenticarte")' in surface
assert "Lock { id: lock }" in shell
assert "SessionHost { lockController: lock }" in shell
for marker in ("signal authenticationSucceeded", "property bool successPending", "root.authenticationSucceeded()", "function releaseAfterSuccess"):
    assert marker in pam, marker
assert "if (passwd.active || successPending)" in pam
# The session lock is released in exactly one place: Pam.releaseAfterSuccess.
assert pam.count("locked = false") == 1
idle = (ROOT / "cortetsu/modules/IdleMonitors.qml").read_text(encoding="utf-8")
for name, source in (("Lock.qml", lock), ("LockSurface.qml", surface), ("IdleMonitors.qml", idle)):
    assert "locked = false" not in source, name
# No unauthenticated unlock route: shortcut, IPC, signal or idle return action.
config = (ROOT / "cortetsu/modules/CortetsuConfig.qml").read_text(encoding="utf-8")
for name, source in (("Lock.qml", lock), ("LockSurface.qml", surface), ("IdleMonitors.qml", idle), ("Pam.qml", pam)):
    assert "unlock()" not in source and "onUnlock" not in source and '"unlock"' not in source, name
assert 'returnAction: "unlock"' not in config
assert 'value.returnAction !== "unlock"' in config and "delete migrated.returnAction" in config
for shadowed in ("Lock.qml", "LockSurface.qml"):
    assert not (ROOT / "cortetsu/base/modules/lock" / shadowed).exists(), shadowed

print("PASS: Lock keeps PAM/session-lock semantics and surfaces live Cortetsu user, keyboard, power and network context")
