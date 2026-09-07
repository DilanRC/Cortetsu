#!/usr/bin/env python3
"""Regression guard for notification dismissal and popup ownership."""

from pathlib import Path


root = Path(__file__).resolve().parents[2]
source = (root / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
close_start = source.index("function close(): void")
close_body = source[close_start:source.index("Component.onCompleted", close_start)]
assert "popup = false" in close_body
assert "closed = true" in close_body
assert "dismissAndRemove()" in close_body
print("PASS: notification close removes popup before model destruction")
