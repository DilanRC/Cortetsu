from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/settings/Content.qml").read_text(encoding="utf-8")
controller = (ROOT / "cortetsu/modules/settings/SettingsController.qml").read_text(encoding="utf-8")
assert "CONTROL SURFACES" in content
assert "schemeColour" in content and "primary" in content
assert "filteredCategories" in controller
assert "This section is connected in stages" in content
assert "Quick Settings" not in content
print("PASS: Settings Center has navigation, progressive disclosure and honest backend boundaries")
