from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
overview = (ROOT / "cortetsu/modules/OverviewController.qml").read_text(encoding="utf-8")

# Sidebar and session close popouts only when they open; the launcher returns
# early when it closes and closes popouts before opening.
assert len(re.findall(r"if \(![\w.]+\)\n\s+(?:hubRoot\.)?closeAllPopouts\(\);", hub)) >= 2
launcher = hub.split("function toggleLauncherFor(screen): void {", 1)[1].split("\n    }\n", 1)[0]
assert launcher.index("closeAllPopouts();") < launcher.index('OverlayPolicy.open(all, state, "launcher");')
assert hub.count("closeAllPopouts();") >= 5
assert "closeAllPopouts();" in overview
print("PASS: retained panels close first-party popouts before opening")
