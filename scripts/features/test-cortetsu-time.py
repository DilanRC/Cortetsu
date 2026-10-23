from pathlib import Path
source = Path(__file__).resolve().parents[2] / "cortetsu/services/Time.qml"
text = source.read_text(encoding="utf-8")
assert "Caelestia" not in text
assert "CortetsuConfig.useTwelveHourClock" in text
assert "SystemClock" in text
assert "precision: SystemClock.Minutes" in text
import re
users = [f for f in source.parents[1].rglob("*.qml") if re.search(r"\bTime\.seconds\b", f.read_text(encoding="utf-8"))]
assert not users, f"Time ticks per minute; these read Time.seconds: {users}"
print("PASS: Cortetsu owns the Time service")
