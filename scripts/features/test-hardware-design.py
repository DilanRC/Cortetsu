import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
hardware = repo / "cortetsu/modules/hardware"
tab = (repo / "cortetsu/components/CortetsuTab.qml").read_text()
legacy = ("Caelestia", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon")

for path in sorted(hardware.glob("*.qml")):
    text = path.read_text()
    for symbol in legacy:
        assert symbol not in text, f"{path.name}: {symbol}"
    assert not re.search(r"(?<!Cortetsu)StateLayer\b", text), path.name

assert "CortetsuStateLayer" in (hardware / "Content.qml").read_text()
assert 'import "../../components"' in (hardware / "Content.qml").read_text()
assert "delegate: CortetsuTab" in (hardware / "Content.qml").read_text()
for marker in ("activeFocusOnTab", "Keys.onEnterPressed", "Keys.onLeftPressed", "Keys.onRightPressed", "signal activated"):
    assert marker in tab, marker
print("PASS: Hardware Center uses Cortetsu visual primitives")
