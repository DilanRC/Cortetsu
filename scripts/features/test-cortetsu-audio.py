import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
audio = (modules / "CortetsuAudio.qml").read_text(encoding="utf-8")
compat = (repo / "cortetsu/services/Audio.qml").read_text(encoding="utf-8")
hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")

for marker in ("Quickshell.Services.Pipewire", "Pipewire.defaultAudioSink", "PwObjectTracker", "CortetsuConfig.maxVolume", "CortetsuConfig.audioIncrement"):
    assert marker in audio, marker
assert "qs.services" not in audio
assert "CortetsuSpectrum" in audio and "CortetsuAudio" in compat
for legacy in ("Caelestia", "CavaProvider", "BeatTracker", "GlobalConfig"):
    assert legacy not in audio + compat, legacy
assert not re.search(r"(?<!Cortetsu)Audio\.", hub)
for marker in ("CortetsuAudio.volume", "CortetsuAudio.muted", "CortetsuAudio.incrementVolume()", "CortetsuAudio.decrementVolume()"):
    assert marker in hub, marker
assert "if (!CortetsuConfig.bar.scrollActions.volume)" in hub

print("PASS: Bottom Hub audio uses the native Cortetsu PipeWire backend")
