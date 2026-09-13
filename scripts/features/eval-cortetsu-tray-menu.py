#!/usr/bin/env python3
"""Small deterministic eval for the tray popup data boundary."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/bar/popouts/CortetsuTrayMenu.qml").read_text(encoding="utf-8")

criteria = {
    "live ObjectModel preserved": "model: opener.children" in source,
    "content-sized menu height": "childrenRect.height" in source,
    "stale activation guarded": "if (!entry)" in source,
    "typed menu delegates": "required property QsMenuEntry modelData" in source,
    "shared popup surface": "CortetsuPopupSurface" in source,
    "content-fit width cap": all(token in source for token in ("menuMaxWidth: 220", "fittedWidth", "naturalWidth", "TextMetrics")),
    "flat rows with game icons": "outlined: false" in source and "implicitSize: 16" in source,
    "async DBus entries are null-safe": all(token in source for token in ("modelData?.icon", "modelData?.text", "modelData?.hasChildren")),
    "single visible panel": "PanelBg" not in source,
    "keyboard navigation preserved": all(token in source for token in ("Keys.onPressed", "Qt.Key_Right", "Qt.Key_Left", "Qt.Key_Escape")),
}
missing = [name for name, passed in criteria.items() if not passed]
assert not missing, f"tray menu eval failed: {missing}"
print(f"Tray menu data-boundary eval: {len(criteria)}/{len(criteria)}")
