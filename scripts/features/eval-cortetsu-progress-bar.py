#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
component = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")
assert "Math.max(0, Math.min(1, root.value))" in component
assert "visible: root.value >= 0 || root.visibleWhenUnavailable" in component
assert component.count("Rectangle {") == 2, "progress primitive should have one track and one fill"
assert component.count("Behavior on width") == 1

consumer_paths = [
    ROOT / "cortetsu/modules/dashboard/Focus.qml",
    ROOT / "cortetsu/modules/hardware/MetricCard.qml",
    ROOT / "cortetsu/modules/osd/Content.qml",
    ROOT / "cortetsu/modules/calendar/Content.qml",
    ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml",
]
assert all("CortetsuProgressBar" in path.read_text(encoding="utf-8") for path in consumer_paths)
assert all("Behavior on width" not in path.read_text(encoding="utf-8") for path in consumer_paths)
print("PASS: progress feedback has one bounded fill, one motion contract and no consumer-owned duplicate")
