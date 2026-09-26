from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/settings/Content.qml").read_text(encoding="utf-8")
system = (ROOT / "cortetsu/modules/settings/SystemPage.qml").read_text(encoding="utf-8")
calibration = (ROOT / "cortetsu/modules/settings/DisplayCalibration.qml").read_text(encoding="utf-8")
network_service = (ROOT / "cortetsu/services/CortetsuSettingsNetwork.qml").read_text(encoding="utf-8")
controller = (ROOT / "cortetsu/modules/settings/SettingsController.qml").read_text(encoding="utf-8")
schemes = (ROOT / "cortetsu/modules/launcher/services/Schemes.qml").read_text(encoding="utf-8")
choice_card = (ROOT / "cortetsu/components/CortetsuChoiceCard.qml").read_text(encoding="utf-8")

assert "SUPERFICIES DE CONTROL" in content
assert "schemeColour" in content and "primary" in content
assert "filteredCategories" in controller
assert 'section.property: "group"' in content
assert "keywords" in controller
assert "This section is connected in stages" not in content
assert "SystemPage" in content
assert "NetworkManager · operaciones y señal en vivo" in system
assert "CortetsuSettingsNetwork.setWifi(enabled)" in system
assert "CortetsuSettingsNetwork.disconnect(modelData.name)" in system
assert "CortetsuNetwork.refresh()" in system
assert "CortetsuAudio.setSourceVolume(nextValue)" in system
assert "CortetsuAudio.setAudioSink(modelData)" in system
assert "Nvibrant.setValue(value * 1024)" in calibration
assert "function refreshNetworks()" in network_service
assert "function connect(" in network_service
assert "function forget(" in network_service
assert "function refreshAll(" in network_service
assert "function refreshDetails(" in network_service
assert "function copyPassword(" in network_service
assert "activeDetails" in network_service
assert "CortetsuSettingsNetwork.copyPassword" in content or "CortetsuSettingsNetwork.copyPassword" in (ROOT / "cortetsu/modules/settings/NetworkPage.qml").read_text(encoding="utf-8")
assert "Dirección IP" in (ROOT / "cortetsu/modules/settings/NetworkPage.qml").read_text(encoding="utf-8")
assert "Brightness.getMonitorForScreen(root.screen)" in system
assert "onMoved: nextValue => CortetsuAudio.setVolume(nextValue)" in system
assert "onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)" in system
assert "Bluetooth.defaultAdapter.enabled" in system
assert "CortetsuPower" in system
assert "Icons.getBatteryIcon" in system
assert "CortetsuWallpapers.applyStatus" in system
assert "CortetsuWallpapers.applyStatusPath" in system
assert 'warningState: CortetsuWallpapers.applyStatus === "failed"' in system
assert "Schemes.apply(schemeCard.schemeData.name, schemeCard.schemeData.flavour)" in content
assert "function apply(name: string, flavour: string)" in schemes
assert "Schemes.catalogCount" in content
assert "Schemes.currentScheme" in content
assert "CortetsuChoiceCard" in content
assert "CortetsuSurface" in choice_card
assert "activeFocusOnTab" in choice_card and "Keys.onSpacePressed" in choice_card
assert "property var swatches" in choice_card
assert "component AppearanceToggle" in content
assert "Esquema activo" in content
assert "component DomainHero" in system
for marker in (
    "CortetsuConfig.dashboard.performance.showCpu",
    "CortetsuConfig.bar.scrollActions.workspaces",
    "CortetsuConfig.launcher.maxShown",
    "CortetsuConfig.notificationDefaultExpireTimeout",
    "CortetsuNotifications.clear()",
    "CortetsuAudio.setStreamVolume",
    "CortetsuAudio.setAudioSource(modelData)",
    "Hypr.monitors?.values ?? []",
):
    assert marker in system, marker
assert "schemeCard.hovered = true" not in content
assert "Layout.preferredHeight: childrenRect.height" in content
assert "implicitHeight: childrenRect.height" not in content
assert "ScrollBar.vertical" in content
assert "ScrollBar.AsNeeded" in content
assert 'title: qsTr("Comportamiento de BottomHub")' in system
for label in ("Estado de la red", "Bluetooth", "Energía"):
    assert f'title: qsTr("{label}")' in system
assert "CortetsuConfig.bar.popouts.statusIcons" in system
for marker in (
    "CortetsuConfig.dashboard.showOnHover",
    "CortetsuConfig.dashboard.showWeather",
    "CortetsuConfig.launcher.showOnHover",
    "CortetsuConfig.bottomHub.statusCluster.audio",
    "CortetsuConfig.bottomHub.statusCluster.network",
    "CortetsuConfig.bottomHub.statusCluster.bluetooth",
    "CortetsuConfig.bottomHub.statusCluster.battery",
    "CortetsuConfig.useFuzzyWallpapers",
    "CortetsuConfig.useFuzzySchemes",
    "CortetsuConfig.toastNowPlaying",
    "CortetsuConfig.notificationExpire",
):
    assert marker in system, marker
assert "WallpaperController.open(root.screen)" in system
assert "root.screenState.cortetsuState?.closeRetainedOverlaysExcept(flag)" in system
assert 'title: qsTr("Segmentos visibles")' in system
assert "CortetsuConfig.bottomHub.segments" in system
overlay_config = (ROOT / "cortetsu/modules/CortetsuOverlayConfig.qml").read_text(encoding="utf-8")
assert "CortetsuConfig.bar.dragThreshold" in overlay_config
assert "CortetsuConfig.launcher.dragThreshold" in overlay_config
assert "import qs." not in content and "import qs." not in system
assert 'import "../CortetsuSearchBar.qml"' in content
assert "compact: true" in content
assert "TextInput" not in content
checks = {
    "appearance preference persists": all(marker in content for marker in (
        "checked: CortetsuConfig.transparencyEnabled",
        "CortetsuConfig.transparencyEnabled = value;",
        "CortetsuConfig.useTwelveHourClock",
        "CortetsuConfig.useFahrenheit",
        "CortetsuConfig.visualiserEnabled",
        "CortetsuConfig.visualiserAutoHide",
        "CortetsuConfig.save();",
    )),
    "system preferences persist": system.count("root.savePreference();") >= 30,
    "display calibration is real and persistent": all(marker in calibration for marker in (
        '"hyprsunset.service"', '"hyprsunset", "temperature"',
        '"hyprsunset", "gamma"', "CortetsuConfig.colorTemperature",
        "CortetsuConfig.colorGamma", "Nvibrant.setValue",
    )),
    "navigation collapses without losing discovery": all(marker in content for marker in (
        "property bool navigationCollapsed", "compact: root.navigationCollapsed",
        "tooltipText: root.navigationCollapsed ? modelData.title",
    )),
    "scheme application state is observable": all(marker in schemes for marker in (
        "pendingScheme", 'applyStatus = "applying"', "applyError", "stderr: StdioCollector", "onExited",
    )),
}
assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Settings persistence eval: {sum(checks.values())}/{len(checks)}")

print("PASS: Settings Center has navigation, live connected pages, honest backend boundaries and scheme ownership")
