#!/usr/bin/env python3
"""Each lint rule fires on a known-bad snippet and stays quiet on the good one."""
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("lint", ROOT / "scripts/verification/qml-design-lint.py")
lint = importlib.util.module_from_spec(spec)
import sys
sys.modules["lint"] = lint
spec.loader.exec_module(lint)

BAD = """
import QtQuick
Item {
    // duration: 900 inside a comment is ignored
    CortetsuSurface {
        radius: 14
        color: "#808080"
        CortetsuSurface { }
        Item {
            width: 24
            height: 24
            MouseArea { anchors.fill: parent }
        }
    }
    Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    Behavior on height { NumberAnimation { duration: 900; easing.type: Easing.OutBounce } }
    NumberAnimation { property: "width"; easing.type: Easing.InCubic }
    Item { scale: shown ? 1 : 0 }
    TextField { placeholderText: "Buscar" }
}
"""

GOOD = """
import QtQuick
Item {
    CortetsuSurface {
        radius: CortetsuDesign.radiusLarge
        color: CortetsuDesign.colorSurface
        Item {
            implicitWidth: CortetsuDesign.controlHeight
            MouseArea { anchors.fill: parent }
        }
    }
    Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline } }
    Item { scale: pressed ? 0.97 : 1 }
    TextField { font.family: CortetsuTypography.uiFamily }
}
"""


def rules(source: str) -> set[str]:
    with tempfile.TemporaryDirectory(dir=ROOT / "cortetsu") as tmp:
        path = Path(tmp) / "Sample.qml"
        path.write_text(source, encoding="utf-8")
        return {f.rule for f in lint.lint_file(path)}


bad = rules(BAD)
expected = set(lint.RULES) - {"color-contrast"}
missing = expected - bad
assert not missing, f"rules did not fire: {sorted(missing)}"
good = rules(GOOD)
assert not good, f"false positives on the good snippet: {sorted(good)}"
assert all(f.rule == "color-contrast" for f in lint.contrast_findings())

# The comment's 900 ms must not count; only the Behavior's does.
with tempfile.TemporaryDirectory(dir=ROOT / "cortetsu") as tmp:
    path = Path(tmp) / "Sample.qml"
    path.write_text(BAD, encoding="utf-8")
    durations = [f for f in lint.lint_file(path) if f.rule == "motion-duration"]
    assert len(durations) == 1 and durations[0].line == 16, durations

# An allow comment with a reason silences its rule on that line or the next;
# one without a reason, or naming another rule, does not.
ALLOWED = """
import QtQuick
Item {
    // design-lint: allow motion-layout-property: the gap grows with the pill
    Behavior on width { NumberAnimation {} }
    Behavior on height { NumberAnimation {} } // design-lint: allow motion-layout-property:
    // design-lint: allow motion-bounce: wrong rule
    Behavior on implicitWidth { NumberAnimation {} }
}
"""
with tempfile.TemporaryDirectory(dir=ROOT / "cortetsu") as tmp:
    path = Path(tmp) / "Sample.qml"
    path.write_text(ALLOWED, encoding="utf-8")
    lines = sorted(f.line for f in lint.lint_file(path) if f.rule == "motion-layout-property")
    assert lines == [6, 8], lines

print("PASS: qml-design-lint rules fire on bad QML and stay quiet on token-based QML")
