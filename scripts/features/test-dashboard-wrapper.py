from pathlib import Path

path = Path(__file__).resolve().parents[2] / "cortetsu/modules/dashboard/Wrapper.qml"
source = path.read_text(encoding="utf-8")
for legacy in ("Caelestia", "GlobalConfig", "FileDialog", "qs.services", "qs.components", "Tokens", "Colours"):
    assert legacy not in source, legacy
assert "screenState?.dashboard === true" in source
assert "Dash {" in source
print("PASS: dashboard wrapper owns activation and geometry")
