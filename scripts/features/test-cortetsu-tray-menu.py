#!/usr/bin/env python3
"""Regression contract for live tray-menu entries and popup sizing."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/bar/popouts/CortetsuTrayMenu.qml").read_text(encoding="utf-8")
identity = (ROOT / "cortetsu/base/modules/bar/SystemTrayIdentity.js").read_text(encoding="utf-8")
bottom_hub = (ROOT / "cortetsu/modules/BottomHubTray.js").read_text(encoding="utf-8")
base_bar = (ROOT / "cortetsu/base/modules/bar/Bar.qml").read_text(encoding="utf-8")
popouts = (ROOT / "cortetsu/base/modules/bar/popouts/Content.qml").read_text(encoding="utf-8")

assert "if (!entry || !entry.enabled || entry.isSeparator)" in source, "tray activation must ignore stale or non-actionable entries"
assert "model: opener.children" in source
assert "childrenRect.height" in source
assert "required property QsMenuEntry modelData" in source
assert "CortetsuPopupSurface" in source
assert "CortetsuStateLayer" in source
assert "Keys.onPressed" in source
assert "StackView.onRemoved: destroy()" not in source, "StackView owns pages created from Components"
assert "initialItem: menuComponent" in source
assert "stack.push(menuComponent, { handle: entry, subMenu: true })" in source
assert "BottomHubTray.nextSelectable" in source
assert "BottomHubTray.indexOfEntry" in source
assert "activeFocusOnTab: enabled" in source
assert "focused: activeFocus" in source
assert "outlined: activeFocus" in source
assert "menuMaxWidth: 220" in source
assert "TextMetrics" in source and "Text.ElideRight" in source
assert "property real naturalWidth" in source
assert "outlined: activeFocus" in source
assert "implicitSize: 16" in source
assert "modelData?.icon ?? \"\"" in source
assert "modelData?.text ?? \"\"" in source
assert "modelData?.hasChildren ?? false" in source
assert "new WeakMap()" in identity and "function entries(items)" in identity
assert "TrayIdentity.instanceKey(item)" in bottom_hub
assert "TrayIdentity.popupName(trayItem.modelData.key)" in base_bar
assert "TrayIdentity.popupName(modelData.key)" in popouts
assert "function popupName(key)" in identity

print("PASS: tray menu keeps the live ObjectModel and sizes from rendered content")
