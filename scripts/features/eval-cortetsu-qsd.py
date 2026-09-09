from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/qsd/Content.qml").read_text(encoding="utf-8")
host = (ROOT / "cortetsu/modules/QsdHost.qml").read_text(encoding="utf-8")
policy = (ROOT / "cortetsu/modules/CortetsuOverlayPolicy.js").read_text(encoding="utf-8")

assert "anchors.right: parent.right" in host and "width: 400" in host
assert "baseColor: Qt.alpha(CortetsuDesign.colorSumi" in host
assert "CortetsuDesign.colorWarning" in content
assert "disabled: value < 0" in content
assert "Bluetooth.defaultAdapter.enabled" in content
assert "UPower.displayDevice" in content
assert "onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)" in content
assert "onMoved: nextValue => CortetsuAudio.setVolume(nextValue)" in content
assert "onMoved: root.brightnessMonitor?.setBrightness(value)" not in content
assert "onMoved: CortetsuAudio.setVolume(value)" not in content
assert "root.screenState.settings = true" in content
assert '"qsd"' in policy
assert "import qs." not in content

print("PASS: QSD eval covers lateral motion, semantic tiles, real levels, Bluetooth, power, settings handoff and overlay exclusion")
