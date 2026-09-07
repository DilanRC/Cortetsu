from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
assert "CortetsuSurface" in segment
assert "networkTooltip" in segment and "networkTooltip" in hub
assert '"sync"' in hub and "CortetsuNetwork.connecting" in hub
assert "signal %2%" in hub
print("PASS: system cluster is unified and exposes connecting, SSID, signal, and semantic status")
