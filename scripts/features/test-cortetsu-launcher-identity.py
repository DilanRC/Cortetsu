from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
assert "function modeLabel()" in content
assert "Theme" in content and "Wallpaper" in content and "Command" in content
assert "Search-first" in content and "Prefix mode" in content
assert "CortetsuDesign.colorPrimaryContainer" in content
assert "CortetsuEvolvingMark" in content
assert "readonly property string markPhase" in content
assert '"Human"' in content and '"Awakening"' in content and '"Monster"' in content
assert "readonly property bool markIntent" in content
assert 'readonly property string markPhase: !(root.screenState?.launcher ?? false)' in content
assert "markPhase: CortetsuWallpapers.applying" not in content
assert '"Cosmic"' not in content
assert "width: 20" in content and "height: 20" in content
print("PASS: launcher exposes distinct Apps, Command, Theme, and Wallpaper modes")
