#!/usr/bin/env python3
"""Evaluate the live notification dismissal ownership contract."""

from pathlib import Path


root = Path(__file__).resolve().parents[2]
source = (root / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
checks = {
    "popup closes immediately": "popup = false" in source,
    "closed history state": "closed = true" in source,
    "model removal handshake": "dismissAndRemove()" in source,
    "popup model is derived": "property list<NotifData> popups: list.filter(item => item.popup)" in (root / "cortetsu/services/Notifs.qml").read_text(encoding="utf-8"),
}
missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
print(f"Notification dismissal eval: {len(checks)}/{len(checks)} (100%)")
