#!/usr/bin/env python3
"""Gate test for the Wave 0 interactive primitive contract."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: missing {label}: {needle}")


surface = (ROOT / "cortetsu/components/CortetsuSurface.qml").read_text()
module_surface = (ROOT / "cortetsu/modules/CortetsuSurface.qml").read_text()
button = (ROOT / "cortetsu/components/CortetsuButton.qml").read_text()
row = (ROOT / "cortetsu/components/CortetsuListRow.qml").read_text()
hub_button = (ROOT / "cortetsu/modules/HubButton.qml").read_text()
app_rail = (ROOT / "cortetsu/modules/CortetsuAppRail.qml").read_text()
tray = (ROOT / "cortetsu/modules/CortetsuTraySegment.qml").read_text()
status = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text()
status_pill = (ROOT / "cortetsu/modules/StatusPill.qml").read_text()
workspaces = (ROOT / "cortetsu/modules/CortetsuWorkspaceDots.qml").read_text()
state_message = (ROOT / "cortetsu/components/CortetsuStateMessage.qml").read_text()
toggle = (ROOT / "cortetsu/components/CortetsuToggle.qml").read_text()
slider = (ROOT / "cortetsu/components/CortetsuSlider.qml").read_text()
inventory = (ROOT / "docs/architecture/qml-surface-inventory.md").read_text()

for needle, label in (
    ("property bool focused", "surface focus state"),
    ("border.width: outlined || focused", "visible focus outline"),
    ("enabled: !disabled", "disabled controls leave the focus chain"),
    ("activeFocusOnTab: true", "stable keyboard tab focus binding"),
    ("Keys.onEnterPressed", "Enter activation"),
    ("Keys.onSpacePressed", "Space activation"),
):
    require(surface + module_surface + button + row + hub_button + app_rail + tray + status + status_pill + workspaces + state_message + toggle + slider, needle, label)

for family in ("BottomHub", "Launcher", "Notifications", "Overview", "OSD", "Toasts"):
    require(inventory, f"| {family} |", f"inventory family {family}")

print("PASS: Wave 0 primitives expose keyboard focus and activation; surface inventory is present")
