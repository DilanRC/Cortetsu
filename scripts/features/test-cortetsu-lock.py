from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
lock = (ROOT / "cortetsu/modules/lock/Lock.qml").read_text(encoding="utf-8")
surface_only = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
# LockSurface owns keys, focus and PAM; LockCard draws what they show.
card = (ROOT / "cortetsu/modules/lock/LockCard.qml").read_text(encoding="utf-8")
# The keyboard probe lives in Lock.qml: one for every surface.
surface = surface_only + card + lock
pam = (ROOT / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")

for marker in ("WlSessionLock", "Pam", 'target: "lock"', "lockReady", "requestLock"):
    assert marker in lock, marker

for marker in (
    "WlSessionLockSurface",
    'import ".."',
    "pam.handleKey",
    "Contraseña",
    "Contraseña incorrecta. Inténtalo de nuevo.",
    "lockBackdrop",
    "CortetsuWallpapers.actualCurrent",
    "CortetsuEvolvingMark",
    'phase: root.markPhase',
    "property bool authenticationAccepted",
    "Qt.callLater(() => keyboardFocus.forceActiveFocus())",
    "onSecureChanged",
    "onActiveFocusChanged",
    "root.lock.secure && !activeFocus",
    'accepted ? "Cosmic" : rejected ? "Monster" : "Ascended"',
    "accepted: root.authenticationAccepted",
    "onAuthenticationSucceeded",
    "unlockTransition",
    "pam.releaseAfterSuccess",
    "if (pam.successPending)",
    "interval: CortetsuDesign.reducedMotion ? 0 : 900",
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
# The surface never copies the desktop and never decides the mark: the card
# derives it from PAM's state and from the acceptance the surface reports.
assert "ScreencopyView" not in surface and "markPhase" not in surface_only
assert "keyboardProbe" not in surface_only
assert 'qsTr("Bloq Mayús")' in card and 'qsTr("CAPS")' not in surface
assert "Pulsa Enter" not in surface
assert "Lock { id: lock }" in shell
assert "SessionHost { lockController: lock }" in shell
for marker in ("signal authenticationSucceeded", "property bool successPending", "root.authenticationSucceeded()", "function releaseAfterSuccess"):
    assert marker in pam, marker
assert "if (passwd.active || successPending)" in pam
# The session lock is released in exactly one place: Pam.releaseAfterSuccess.
assert pam.count("locked = false") == 1
idle = (ROOT / "cortetsu/modules/IdleMonitors.qml").read_text(encoding="utf-8")
for name, source in (("Lock.qml", lock), ("LockSurface.qml", surface_only), ("LockCard.qml", card), ("IdleMonitors.qml", idle)):
    assert "locked = false" not in source, name
# No unauthenticated unlock route: shortcut, IPC, signal or idle return action.
config = (ROOT / "cortetsu/modules/CortetsuConfig.qml").read_text(encoding="utf-8")
for name, source in (("Lock.qml", lock), ("LockSurface.qml", surface_only), ("LockCard.qml", card), ("IdleMonitors.qml", idle), ("Pam.qml", pam)):
    assert "unlock()" not in source and "onUnlock" not in source and '"unlock"' not in source, name
assert 'returnAction: "unlock"' not in config
assert 'value.returnAction !== "unlock"' in config and "delete migrated.returnAction" in config
for shadowed in ("Lock.qml", "LockSurface.qml"):
    assert not (ROOT / "cortetsu/base/modules/lock" / shadowed).exists(), shadowed

print("PASS: Lock keeps PAM/session-lock semantics and surfaces live Cortetsu user, keyboard, power and network context")
