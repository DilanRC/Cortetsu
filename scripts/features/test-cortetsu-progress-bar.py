#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
component = ROOT / "cortetsu/components/CortetsuProgressBar.qml"
text = component.read_text(encoding="utf-8")

for token in (
    "property real value",
    "property bool visibleWhenUnavailable",
    "property color trackColor",
    "property color fillColor",
    "property real barHeight",
    "property real barRadius",
    "property int motionDuration",
    "readonly property real normalizedValue",
    "visible: root.value >= 0 || root.visibleWhenUnavailable",
    "Behavior on width",
    "CortetsuDesign.motionStandardMs",
):
    assert token in text, f"progress primitive contract missing: {token}"

consumers = {
    "cortetsu/modules/dashboard/Focus.qml": "value: root.progress()",
    "cortetsu/modules/hardware/MetricCard.qml": "value: root.progress",
    "cortetsu/modules/osd/Content.qml": "value: indicator.modelData.value",
}
for name, token in consumers.items():
    consumer = (ROOT / name).read_text(encoding="utf-8")
    assert "CortetsuProgressBar" in consumer, f"{name} does not use shared progress primitive"
    assert token in consumer, f"{name} lost its progress source"

print("PASS: QSD-adjacent system feedback, Dashboard focus and Hardware metrics share CortetsuProgressBar")
