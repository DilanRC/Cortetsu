from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
full_osd = ROOT / "cortetsu/modules/osd/FullContent.qml"
content = full_osd.read_text(encoding="utf-8")
action_tile = (ROOT / "cortetsu/components/CortetsuActionTile.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
state = (ROOT / "cortetsu/components/ScreenState.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")
hypr = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")

assert full_osd.is_file()
assert not (ROOT / "cortetsu/modules/qsd").exists()
assert "QsdHost {}" not in shell
assert 'const target = drawer === "qsd" ? "osd" : drawer;' in shortcuts
for marker in (
    "Brightness.getMonitorForScreen",
    "CortetsuAudio.setVolume",
    "CortetsuNotifications.dnd",
    "Red no disponible",
    "Bluetooth.defaultAdapter.enabled",
    "connectedBluetoothCount",
    "CortetsuPower",
    "batteryPercent",
    "openSettings",
    "CortetsuActionTile",
    "CortetsuEvolvingMark",
    "readonly property string markPhase",
    'phase: root.markPhase',
    'id: soundTile',
    'id: dndTile',
    'id: bluetoothTile',
    'Grabar pantalla',
    'Mantener activo',
    'Activar modo juego',
    'function closeQsd(): void',
    'readonly property real batteryValue:',
    'CortetsuPower.value',
    'readonly property bool batteryAvailable:',
):
    assert marker in content, marker
assert "required property ShellScreen screen" in content
assert not (ROOT / "cortetsu/modules/QsdHost.qml").exists()
assert 'qsd: null' not in window
assert "property bool qsd" not in state
assert "qsdEdgeHovered" not in state
assert "qsdDrawerHovered" not in state
assert "qsdOpenedByShortcut" not in state
assert 'name: "qsd"' in shortcuts
assert 'root.toggleExclusive(state, "osd")' in shortcuts
assert 'const target = drawer === "qsd" ? "osd" : drawer;' in shortcuts
assert 'onClicked: root.closeQsd()' in content
assert 'hl.dsp.global("cortetsu:osd")' in hypr

# The connectivity tile is intentionally status-only: OSD must not pretend it
# can toggle Wi-Fi until the native NetworkManager service exposes that write.
assert 'label: root.networkName' in content
assert 'clickable: false' in content
assert 'icon: CortetsuAudio.muted ? "volume_off" : "volume_up"' in content
assert 'highlighted: CortetsuNotifications.dnd' in content
assert content.count('warning: false') >= 2
assert 'warning: CortetsuNotifications.dnd' not in content
assert 'UPower.displayDevice.percentage' not in content
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
assert "Layout.preferredWidth: 32" in content and "Layout.preferredHeight: 32" in content
assert 'phase: "Ascended"' not in content

print("PASS: OSD is a first-party right-side surface with brightness, audio, DND, Bluetooth, power and network context")
