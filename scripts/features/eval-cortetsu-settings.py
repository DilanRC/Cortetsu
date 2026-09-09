from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/settings/Content.qml").read_text(encoding="utf-8")
system = (ROOT / "cortetsu/modules/settings/SystemPage.qml").read_text(encoding="utf-8")
controller = (ROOT / "cortetsu/modules/settings/SettingsController.qml").read_text(encoding="utf-8")
schemes = (ROOT / "cortetsu/modules/launcher/services/Schemes.qml").read_text(encoding="utf-8")

assert "CONTROL SURFACES" in content
assert "schemeColour" in content and "primary" in content
assert "filteredCategories" in controller
assert "This section is connected in stages" not in content
assert "SystemPage" in content
assert "Native NetworkManager readback; no fake controls" in system
assert "Brightness.getMonitorForScreen(root.screen)" in system
assert "CortetsuAudio.setVolume(value)" in system
assert "Bluetooth.defaultAdapter.enabled" in system
assert "UPower.displayDevice" in system
assert "Icons.getBatteryIcon" in system
assert "Schemes.apply(schemeCard.schemeData.name, schemeCard.schemeData.flavour)" in content
assert "function apply(name: string, flavour: string)" in schemes
assert "Schemes.catalogCount" in content
assert "Schemes.currentScheme" in content
assert "Layout.preferredHeight: childrenRect.height" in content
assert "implicitHeight: childrenRect.height" not in content
assert "ScrollBar.vertical" in content
assert "ScrollBar.AsNeeded" in content
assert 'title: qsTr("Visible status controls")' in system
for label in ("Volume", "Network", "Bluetooth", "Battery"):
    assert f'title: qsTr("{label}")' in system
assert "CortetsuConfig.bottomHub.statusCluster" in system
assert 'title: qsTr("Visible segments")' in system
assert "CortetsuConfig.bottomHub.segments" in system
overlay_config = (ROOT / "cortetsu/modules/CortetsuOverlayConfig.qml").read_text(encoding="utf-8")
assert "CortetsuConfig.bar.dragThreshold" in overlay_config
assert "CortetsuConfig.launcher.dragThreshold" in overlay_config
assert "import qs." not in content and "import qs." not in system

print("PASS: Settings Center has navigation, live connected pages, honest backend boundaries and scheme ownership")
