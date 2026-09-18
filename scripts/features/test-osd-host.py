from pathlib import Path

repo = Path(__file__).resolve().parents[2]
for name in ("Wrapper.qml", "Content.qml"):
    source = (repo / "cortetsu/modules/osd" / name).read_text(encoding="utf-8")
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, f"{name}: {legacy}"
assert "screenState?.osd" in (repo / "cortetsu/modules/osd/Wrapper.qml").read_text(encoding="utf-8")
qsd = (repo / "cortetsu/modules/osd/FullContent.qml").read_text(encoding="utf-8")
assert "CortetsuAudio.setVolume" in qsd
assert "CortetsuSurface" in qsd
assert "CortetsuActionTile" in qsd
print("PASS: OSD host uses first-party audio, brightness, and state")
