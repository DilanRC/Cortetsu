#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/hardware/Content.qml").read_text(encoding="utf-8")
tab = (ROOT / "cortetsu/components/CortetsuTab.qml").read_text(encoding="utf-8")

assert 'import "../../components"' in content
assert "delegate: Item" in content
assert "id: tabDelegate" in content
assert "onPreviousRequested: root.selectAdjacentTab(-1)" in content
assert "onNextRequested: root.selectAdjacentTab(1)" in content
assert "required property int index" in content
assert "index: tabDelegate.index" in content
assert "focus: root.selected && !root.disabled" in tab
assert "enabled: !root.disabled" in tab
assert "activeFocusOnTab: true" in tab
assert "Keys.onSpacePressed" in tab
assert "outlined: root.activeFocus || root.selected" in tab
assert content.count("{ label:") == 10
assert "count: 10" in content
assert 'import "Navigation.js" as HardwareNavigation' in content
assert "HardwareNavigation.pageForKey(" in content
assert "HardwareNavigation.handlesPageKey" in content
assert "HardwareNavigation.isEscape" in content
assert "Math.min(9, root.currentPage + delta)" in content
assert "contentWidth: tabRow.implicitWidth" in content
assert "tabs.contentWidth - tabs.width" in content
assert "automationComponent" in content and "currentPage === 6" in content
assert "startupComponent" in content
print("PASS: Hardware tabs share selected, hover, focus and arrow-key behavior")
