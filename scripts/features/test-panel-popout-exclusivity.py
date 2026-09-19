from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
overview = (ROOT / "cortetsu/modules/OverviewController.qml").read_text(encoding="utf-8")

assert hub.count("if (!wasOpen)\n            closeAllPopouts();") >= 3
assert hub.count("closeAllPopouts();") >= 5
assert "closeAllPopouts();" in overview
print("PASS: retained panels close first-party popouts before opening")
