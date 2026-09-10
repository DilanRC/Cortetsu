#!/usr/bin/env python3
"""Gate contract for the typed monitor-local state boundary."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
state = (ROOT / "cortetsu/modules/CortetsuScreenState.qml").read_text(encoding="utf-8")
policy = (ROOT / "cortetsu/modules/OverlayPolicy.js").read_text(encoding="utf-8")
controller_paths = sorted((ROOT / "cortetsu/modules").glob("*Controller.qml"))

assert "function setFlag(flag: string, value: bool): bool" in state
assert 'return setRetained(flag, value);' in state
assert 'legacyState[flag] = value;' in state
assert 'typeof state.setFlag === "function"' in policy
assert "setFlag(state, flag, false)" in policy

for path in controller_paths:
    text = path.read_text(encoding="utf-8")
    assert ".legacyState" not in text, path
    if "OverlayPolicy.close" in text:
        assert "cortetsuState" in text, path

print("PASS: controllers consume CortetsuScreenState without leaking the legacy backing object")
