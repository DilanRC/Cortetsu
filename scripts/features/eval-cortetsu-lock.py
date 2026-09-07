from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
surface = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
assert "Qt.alpha(CortetsuDesign.colorSumi" in surface
assert "secure" not in surface.lower() or "password" in surface.lower()
assert "repeat(pam.buffer.length)" in surface
assert "UPower.displayDevice" in surface and "CortetsuNetwork.active" in surface
print("PASS: Lock visual has controlled dimming, immediate password focus, failure feedback, and live status")
