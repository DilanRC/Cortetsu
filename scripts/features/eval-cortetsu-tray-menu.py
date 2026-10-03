#!/usr/bin/env python3
"""Small deterministic eval for the tray popup data boundary."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/bar/popouts/CortetsuTrayMenu.qml").read_text(encoding="utf-8")
bottom_hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
popout_state = (ROOT / "cortetsu/base/modules/bar/popouts/PopoutState.qml").read_text(encoding="utf-8")
popout_wrapper = (ROOT / "cortetsu/modules/bar/popouts/Wrapper.qml").read_text(encoding="utf-8")
popouts = (ROOT / "cortetsu/base/modules/bar/popouts/Content.qml").read_text(encoding="utf-8")

criteria = {
    "live ObjectModel preserved": "model: opener.children" in source,
    "content-sized menu height follows live children": all(token in source for token in ("readonly property real naturalHeight", "childrenRect.height + padding * 2")),
    "position follows current page natural height": all(token in source for token in ("currentPage?.naturalHeight", "menuContentHeight: currentPage?.naturalHeight ?? 48", "readonly property int menuDepth")),
    "runtime inspector exposes tray routing and geometry": all(token in bottom_hub for token in ("itemKey:", "popupName:", "shouldBeActive:", "loaderActive:", "menuHandle:", "stackDepth:", "popupY:", "popupHeight:")),
    "tray destruction closes through the owning popup": all(token in popout_state + popout_wrapper + popouts for token in ("signal closeRequested()", "onCloseRequested: root.close()", "root.popouts.close()", "shouldBeActive && menuReady")),
    "stale and non-actionable activation guarded": "if (!entry || !entry.enabled || entry.isSeparator)" in source,
    "typed menu delegates": "required property QsMenuEntry modelData" in source,
    "shared popup surface": "CortetsuPopupSurface" in source,
    "content-fit width cap": all(token in source for token in ("menuMaxWidth: 220", "fittedWidth", "naturalWidth", "TextMetrics")),
    "flat focusable rows with game icons": all(token in source for token in ("radiusValue: 0", "outlined: activeFocus", "implicitSize: 16")),
    "async DBus entries are null-safe": all(token in source for token in ("modelData?.icon", "modelData?.text", "modelData?.hasChildren")),
    "single visible panel": "PanelBg" not in source,
    "keyboard navigation preserved": all(token in source for token in ("Keys.onPressed", "Qt.Key_Right", "Qt.Key_Left", "Qt.Key_Escape")),
    "keyboard focus skips separators and disabled rows": "activeFocusOnTab: enabled" in source,
    "focus identity survives model reorder": "BottomHubTray.indexOfEntry" in source,
}
missing = [name for name, passed in criteria.items() if not passed]
assert not missing, f"tray menu eval failed: {missing}"
print(f"Tray menu data-boundary eval: {len(criteria)}/{len(criteria)}")
