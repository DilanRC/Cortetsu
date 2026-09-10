from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/qsd/Content.qml").read_text(encoding="utf-8")
action_tile = (ROOT / "cortetsu/components/CortetsuActionTile.qml").read_text(encoding="utf-8")
host = (ROOT / "cortetsu/modules/QsdHost.qml").read_text(encoding="utf-8")
policy = (ROOT / "cortetsu/modules/CortetsuOverlayPolicy.js").read_text(encoding="utf-8")
power = (ROOT / "cortetsu/services/CortetsuPower.qml").read_text(encoding="utf-8")

assert "anchors.right: parent.right" in host and "width: 400" in host
assert "baseColor: Qt.alpha(CortetsuDesign.colorSumi" in host
assert "highlighted: CortetsuNotifications.dnd" in content
assert 'icon: CortetsuAudio.muted ? "volume_off" : "volume_up"' in content
assert 'warning: false' in content
assert 'color: CortetsuAudio.muted ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorPrimary' in content
assert "disabled: value < 0" in content
assert "Bluetooth.defaultAdapter.enabled" in content
assert "CortetsuPower" in content
assert "onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)" in content
assert "onMoved: nextValue => CortetsuAudio.setVolume(nextValue)" in content
assert "onMoved: root.brightnessMonitor?.setBrightness(value)" not in content
assert "onMoved: CortetsuAudio.setVolume(value)" not in content
assert "root.screenState.settings = true" in content
assert '"qsd"' in policy
assert "import qs." not in content
assert "CortetsuActionTile" in content
assert "CortetsuEvolvingMark" in content
assert 'phase: root.markPhase' in content
assert 'markPressed: soundTile.pressed || dndTile.pressed || bluetoothTile.pressed' in content
assert ' ? "Monster"' in content and ' ? "Awakening"' in content and ': "Human"' in content
assert "Layout.preferredWidth: 24" in content and "Layout.preferredHeight: 24" in content
assert 'phase: "Ascended"' not in content
assert "activeFocusOnTab" in action_tile and "Keys.onSpacePressed" in action_tile
assert "property bool warning" in action_tile
assert "onEntered: tile.hovered = true" not in content
checks = {
    "explicit close clears shortcut pin": all(marker in content for marker in (
        "function closeQsd(): void",
        "state.qsdOpenedByShortcut = false",
        "state.qsdEdgeHovered = false",
        "state.qsdDrawerHovered = false",
        "onClicked: root.closeQsd()",
    )),
    "battery capability is finite and clamped": all(marker in content for marker in (
        "readonly property real batteryValue:",
        "CortetsuPower.value",
        "batteryAvailable",
    )) and all(marker in power for marker in (
        "Number.isFinite(raw)",
        "Math.max(0, Math.min(1, raw))",
        "property bool available",
    )) and "UPower.displayDevice.percentage" not in content,
    "DND is a selected preference": "highlighted: CortetsuNotifications.dnd" in content
        and "warning: CortetsuNotifications.dnd" not in content,
}
assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"QSD lifecycle/state eval: {sum(checks.values())}/{len(checks)}")

print("PASS: QSD eval covers lateral motion, semantic tiles, real levels, Bluetooth, power, settings handoff and overlay exclusion")
