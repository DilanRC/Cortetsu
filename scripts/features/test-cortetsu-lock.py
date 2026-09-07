from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
lock = (ROOT / "cortetsu/modules/lock/Lock.qml").read_text(encoding="utf-8")
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
for marker in ("WlSessionLock", "Pam", 'target: "lock"', "sessionLock.unlock"):
    assert marker in lock, marker
for marker in ("WlSessionLockSurface", "pam.handleKey", "Password", "Authentication failed", "ScreencopyView", "cortetsu-mark.svg"):
    assert marker in surface, marker
assert "Lock { id: lock }" in shell
print("PASS: Lock keeps the PAM/session-lock backend and uses a first-party Cortetsu surface")
