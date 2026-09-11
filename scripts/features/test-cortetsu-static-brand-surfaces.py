#!/usr/bin/env python3
"""Gate contract for static first-party surfaces using the shared mark renderer."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SURFACES = {
    "osd": (ROOT / "cortetsu/modules/osd/Content.qml", "width: 24"),
    "dashboard": (ROOT / "cortetsu/modules/dashboard/Dash.qml", "Layout.preferredWidth: 38"),
    "settings": (ROOT / "cortetsu/modules/settings/Content.qml", "Layout.preferredWidth: 72"),
}
QSD = ROOT / "cortetsu/modules/qsd/Content.qml"
LOCK = ROOT / "cortetsu/modules/lock/LockSurface.qml"
SESSION = ROOT / "cortetsu/modules/SessionHost.qml"

for name, (path, size_marker) in SURFACES.items():
    content = path.read_text(encoding="utf-8")
    assert "CortetsuEvolvingMark" in content, name
    assert 'phase: "Ascended"' in content, name
    assert "animated: false" in content, name
    assert "monochrome: true" in content, name
    assert "monochromeColor: CortetsuDesign.colorWashi" in content, name
    assert size_marker in content, (name, size_marker)
    assert 'source: Quickshell.shellPath("assets/branding/cortetsu-mark-ascended.svg")' not in content, name

qsd = QSD.read_text(encoding="utf-8")
assert "CortetsuEvolvingMark" in qsd
assert 'phase: root.markPhase' in qsd
assert "Layout.preferredWidth: 24" in qsd and "Layout.preferredHeight: 24" in qsd
assert "monochrome: true" in qsd
assert "monochromeColor: CortetsuDesign.colorWashi" in qsd
assert 'source: Quickshell.shellPath("assets/branding/cortetsu-mark-ascended.svg")' not in qsd

lock = LOCK.read_text(encoding="utf-8")
assert "CortetsuEvolvingMark" in lock
assert 'phase: root.markPhase' in lock
assert "Layout.preferredWidth: 64" in lock and "Layout.preferredHeight: 64" in lock
assert "monochrome: true" in lock
assert "monochromeColor: CortetsuDesign.colorWashi" in lock
assert 'source: Quickshell.shellPath("assets/branding/cortetsu-mark-ascended.svg")' not in lock

session = SESSION.read_text(encoding="utf-8")
assert "CortetsuEvolvingMark" in session
assert 'phase: window.open ? "Awakening" : "Human"' in session
assert "width: 44; height: 44" in session
assert "MouseArea" not in session

print("PASS: static and contextual product surfaces share the fixed-size mark renderer")
