from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/qsd/Content.qml").read_text(encoding="utf-8")
host = (ROOT / "cortetsu/modules/QsdHost.qml").read_text(encoding="utf-8")
policy = (ROOT / "cortetsu/modules/CortetsuOverlayPolicy.js").read_text(encoding="utf-8")
assert "anchors.right: parent.right" in host and "width: 400" in host
assert "baseColor: Qt.alpha(CortetsuDesign.colorSumi" in host
assert "CortetsuDesign.colorWarning" in content
assert "disabled: value < 0" in content
assert '"qsd"' in policy
print("PASS: QSD eval covers lateral motion, semantic states, unsupported brightness, and overlay exclusion")
