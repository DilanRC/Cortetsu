from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
qsd = ROOT / "cortetsu/modules/qsd"
content = (qsd / "Content.qml").read_text(encoding="utf-8")
action_tile = (ROOT / "cortetsu/components/CortetsuActionTile.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
host = (ROOT / "cortetsu/modules/QsdHost.qml").read_text(encoding="utf-8")
state = (ROOT / "cortetsu/components/ScreenState.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")
hypr = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")

assert (qsd / "qmldir").is_file()
for marker in (
    "Brightness.getMonitorForScreen",
    "CortetsuAudio.setVolume",
    "CortetsuNotifications.dnd",
    "Network unavailable",
    "Bluetooth.defaultAdapter.enabled",
    "connectedBluetoothCount",
    "Quickshell.Services.UPower",
    "batteryPercent",
    "openSettings",
    "CortetsuActionTile",
    "CortetsuEvolvingMark",
    "readonly property string markPhase",
    'phase: root.markPhase',
    'id: soundTile',
    'id: dndTile',
    'id: bluetoothTile',
    'function closeQsd(): void',
    'state.qsdOpenedByShortcut = false',
    'state.qsdEdgeHovered = false',
    'state.qsdDrawerHovered = false',
    'readonly property real batteryValue:',
    'Number.isFinite(value)',
    'readonly property bool batteryAvailable:',
):
    assert marker in content, marker
assert "required property ShellScreen screen" in content
assert "screen: window.modelData" in host
assert "qsdEdgeHovered" in host
assert "qsdDrawerHovered" in host
assert "qsdOpenedByShortcut" in host
assert "interval: 260" in host
for marker in ("Variants", "StyledWindow", 'name: "qsd"', "WlrLayer.Overlay", "width: 400", "Content"):
    assert marker in host, marker
assert 'qsd: null' in window
assert "property bool qsd" in state and "|| qsd" in state
assert "property bool qsdEdgeHovered" in state
assert "property bool qsdDrawerHovered" in state
assert "property bool qsdOpenedByShortcut" in state
assert 'name: "qsd"' in shortcuts
assert 'state.qsdOpenedByShortcut = state.qsd' in shortcuts
assert 'onClicked: root.closeQsd()' in content
assert 'hl.dsp.global("cortetsu:qsd")' in hypr

# The connectivity tile is intentionally status-only: QSD must not pretend it
# can toggle Wi-Fi until the native NetworkManager service exposes that write.
assert 'label: root.networkName' in content
assert 'clickable: false' in content
assert 'icon: CortetsuAudio.muted ? "volume_off" : "volume_up"' in content
assert 'highlighted: CortetsuNotifications.dnd' in content
assert content.count('warning: false') >= 2
assert 'warning: CortetsuNotifications.dnd' not in content
assert 'Math.round(UPower.displayDevice.percentage * 100)' not in content
assert 'color: CortetsuAudio.muted ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorPrimary' in content
assert 'onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)' in content
assert 'onMoved: nextValue => CortetsuAudio.setVolume(nextValue)' in content
assert 'onMoved: root.brightnessMonitor?.setBrightness(value)' not in content
assert 'onMoved: CortetsuAudio.setVolume(value)' not in content
assert "import qs." not in content
assert 'import "../../components"' in content
assert 'import "../../services"' in content
assert "CortetsuSurface" in action_tile
assert "focus: false" in action_tile
assert "activeFocusOnTab" in action_tile
assert "Keys.onEnterPressed" in action_tile
assert "Keys.onSpacePressed" in action_tile
assert "onEntered: tile.hovered = true" not in content
assert "onPressedChanged: tile.pressed" not in content
assert "focus: true" in content
assert 'markPressed: soundTile.pressed || dndTile.pressed || bluetoothTile.pressed' in content
assert 'markIntent: markPressed' in content
assert ' ? "Monster"' in content and ' ? "Awakening"' in content and ': "Human"' in content
assert "Layout.preferredWidth: 24" in content and "Layout.preferredHeight: 24" in content
assert 'phase: "Ascended"' not in content

print("PASS: QSD is a first-party right-side surface with brightness, audio, DND, Bluetooth, power and network context")
