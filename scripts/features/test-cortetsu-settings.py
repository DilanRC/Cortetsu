#!/usr/bin/env python3
"""Static contracts for the first-party Cortetsu Settings Center."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
modules = ROOT / "cortetsu/modules"
settings = modules / "settings"

host = (modules / "SettingsHost.qml").read_text(encoding="utf-8")
wrapper = (settings / "Wrapper.qml").read_text(encoding="utf-8")
content = (settings / "Content.qml").read_text(encoding="utf-8")
system = (settings / "SystemPage.qml").read_text(encoding="utf-8")
schemes = (modules / "launcher/services/Schemes.qml").read_text(encoding="utf-8")
state = (ROOT / "cortetsu/components/ScreenState.qml").read_text(encoding="utf-8")
shortcuts = (modules / "Shortcuts.qml").read_text(encoding="utf-8")
user_hypr = (ROOT / "config/hypr-user.lua").read_text(encoding="utf-8")
base_hypr = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
runtime_builder = (ROOT / "cortetsu/bin/build-runtime.sh").read_text(encoding="utf-8")

for filename in ("SettingsController.qml", "Wrapper.qml", "Content.qml", "SystemPage.qml"):
    assert (settings / filename).is_file(), filename
choice_card = ROOT / "cortetsu/components/CortetsuChoiceCard.qml"
assert choice_card.is_file()
choice_card_text = choice_card.read_text(encoding="utf-8")

# Settings follows the actual ShellScreen all the way to hardware controls.
assert "CortetsuShellState.forScreen(modelData)" in host
assert "CortetsuShellState.forActive()" not in host
assert "screen: window.modelData" in host
assert "required property var screen" in wrapper
assert "screen: root.screen" in wrapper
assert "required property var screen" in content
assert "SystemPage" in content and "screen: root.screen" in content

# Placeholder-only pages are gone; every non-appearance/about category owns a page.
assert "This section is connected in stages" not in content
for section in (
    "desktop", "bottomhub", "launcher", "notifications", "network", "bluetooth",
    "audio", "power", "display", "input", "shortcuts", "wallpaper",
):
    assert f'root.section === "{section}"' in system, section

# Connected pages use real first-party/native backends rather than simulated state.
for marker in (
    "Brightness.getMonitorForScreen(root.screen)",
    "onMoved: nextValue => CortetsuAudio.setVolume(nextValue)",
    "CortetsuNotifications.dnd",
    "CortetsuNetwork.active",
    "Bluetooth.defaultAdapter.enabled",
    "UPower.displayDevice",
    'setRetained(flag, true)',
    "CortetsuWallpapers.actualCurrent",
    "CortetsuWallpapers.applyStatus",
    "CortetsuWallpapers.applyStatusPath",
    "Icons.getBatteryIcon",
):
    assert marker in system, marker
assert 'root.openRetained("displayManager")' in system
assert 'root.openRetained("wallpaperManager")' in system
assert "Native NetworkManager readback; no fake controls" in system
assert 'title: qsTr("Volume scroll")' in system
assert 'title: qsTr("Brightness scroll")' not in system
assert 'title: qsTr("Open on hover")' not in system
assert 'onMoved: nextValue => CortetsuAudio.setVolume(nextValue)' in system
assert 'onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)' in system
assert 'onMoved: CortetsuAudio.setVolume(value)' not in system
assert 'onMoved: root.brightnessMonitor?.setBrightness(value)' not in system

# Scheme selection is a single owned transaction and refreshes the active highlight.
for marker in (
    "function apply(name: string, flavour: string)",
    '["cortetsu-scheme", "set", "-n", name, flavour]',
    "readonly property bool applying: applyScheme.running",
    "root.reload();",
    "Unable to read the scheme catalog",
):
    assert marker in schemes, marker
assert "Schemes.apply(schemeCard.schemeData.name, schemeCard.schemeData.flavour)" in content
assert "Schemes.currentScheme" in content
assert "Schemes.catalogCount" in content
assert "CortetsuChoiceCard" in content
assert "activeFocusOnTab" in choice_card_text
assert "Keys.onEnterPressed" in choice_card_text
assert "Keys.onSpacePressed" in choice_card_text
assert "schemeCard.hovered = true" not in content
assert "onPressedChanged: schemeCard.pressed" not in content
assert "Quickshell.execDetached([\"cortetsu-scheme\", \"set\"" not in content
assert "Layout.preferredHeight: childrenRect.height" in content
assert "implicitHeight: childrenRect.height" not in content
assert "import QtQuick.Controls" in content
assert "ScrollBar.vertical" in content
assert "scroller.contentHeight > scroller.height" in content
assert 'title: qsTr("Visible segments")' in system
assert 'value: CortetsuWallpapers.applyStatus === "applying"' in system
assert 'warningState: CortetsuWallpapers.applyStatus === "failed"' in system
for label in ("Mode and workspaces", "App rail", "Tray", "Status cluster"):
    assert f'title: qsTr("{label}")' in system
assert "CortetsuConfig.bottomHub.segments" in system

# User overrides agree with canonical first-party bindings, avoiding a double-open
# of Utilities plus QSD/Settings for the same keystroke.
assert 'create_bind("SUPER + I", hl.dsp.global("cortetsu:settings"))' in base_hypr
assert 'create_bind("SUPER + SLASH", hl.dsp.global("cortetsu:qsd"))' in base_hypr
assert '"SUPER + I",\n    hl.dsp.global("cortetsu:settings")' in user_hypr
assert '"SUPER + Slash",\n    hl.dsp.global("cortetsu:qsd")' in user_hypr
assert '"SUPER + I",\n    hl.dsp.global("cortetsu:utilities")' not in user_hypr
assert 'name: "settings"' in shortcuts and 'name: "qsd"' in shortcuts

# Existing Settings host/runtime identity contract remains intact.
for marker in ('name: "settings"', "WlrLayer.Overlay", "Exclusive", "Wrapper"):
    assert marker in host, marker
assert "property bool settings" in state and "|| settings" in state
assert 'cortetsu/assets/branding' in runtime_builder and 'STAGING/assets/branding' in runtime_builder
assert 'import "../CortetsuSearchBar.qml"' in content
assert "CortetsuSearchBar {" in content
assert "compact: true" in content
assert "TextInput" not in content
for source in (content, system):
    assert "import qs." not in source
assert 'import "../../components"' in content
assert 'import "../launcher/services"' in content
assert 'import "../../services"' in system
assert 'import "../../utils"' in system

print("PASS: Settings owns per-monitor state, schemes, connected pages, retained handoffs and aligned SUPER+I/SUPER+/ bindings")
