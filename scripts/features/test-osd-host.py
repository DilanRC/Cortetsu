from pathlib import Path

repo = Path(__file__).resolve().parents[2]
for name in ("Wrapper.qml", "Content.qml"):
    source = (repo / "cortetsu/modules/osd" / name).read_text(encoding="utf-8")
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, f"{name}: {legacy}"
assert "screenState?.osd" in (repo / "cortetsu/modules/osd/Wrapper.qml").read_text(encoding="utf-8")
qsd = (repo / "cortetsu/modules/osd/FullContent.qml").read_text(encoding="utf-8")
assert "CortetsuAudio.setVolume" in qsd
assert "CortetsuInkLabel" in qsd and "CortetsuBrushStroke" in qsd
assert "CortetsuActionTile" in qsd
print("PASS: OSD host uses first-party audio, brightness, and state")

# Ink: tiles press a seal while on; the popup ground is the shared ink one.
tile = (repo / "cortetsu/components/CortetsuActionTile.qml").read_text(encoding="utf-8")
assert 'property string seal: ""' in tile and "hanko.stamp()" in tile
assert qsd.count('seal: "') == 6
grain = (repo / "cortetsu/components/CortetsuGrain.qml").read_text(encoding="utf-8")
assert "import Quickshell" not in grain, "qmltestrunner cannot load Quickshell"
