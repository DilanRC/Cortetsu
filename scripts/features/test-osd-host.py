from pathlib import Path

repo = Path(__file__).resolve().parents[2]
for name in ("Wrapper.qml", "Content.qml"):
    source = (repo / "cortetsu/modules/osd" / name).read_text(encoding="utf-8")
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, f"{name}: {legacy}"
assert "screenState?.osd" in (repo / "cortetsu/modules/osd/Wrapper.qml").read_text(encoding="utf-8")
assert "CortetsuAudio.incrementVolume" in (repo / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "CortetsuSurface" in (repo / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
print("PASS: OSD host uses first-party audio, brightness, and state")
