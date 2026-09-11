from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
typography = (ROOT / "cortetsu/modules/CortetsuTypography.js").read_text(encoding="utf-8")
datetime = (ROOT / "cortetsu/modules/dashboard/dash/DateTime.qml").read_text(encoding="utf-8")
media = (ROOT / "cortetsu/modules/dashboard/dash/Media.qml").read_text(encoding="utf-8")
dashboard = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
focus = (ROOT / "cortetsu/modules/dashboard/Focus.qml").read_text(encoding="utf-8")
launcher = (ROOT / "cortetsu/modules/launcher/AppList.qml").read_text(encoding="utf-8")

for alias in (
    "displaySmallPx",
    "displayMediumPx",
    "displayClockPx",
    "displayLargePx",
    "displayHeroPx",
    "iconFeaturePx",
    "iconHeroPx",
):
    assert f"var {alias} =" in typography, alias

assert 'import "../../CortetsuText.qml"' in datetime
assert "CortetsuText {" in datetime
assert "font.pixelSize:" not in datetime
assert "CortetsuIcon {" in media
assert "CortetsuText {" in media
assert "font.pixelSize:" not in media
assert "textSize: CortetsuTypography.displayClockPx" in dashboard
assert "textSize: CortetsuTypography.displayHeroPx" in dashboard
assert "textSize: CortetsuTypography.displayLargePx" in dashboard
assert "textSize: CortetsuTypography.displayClockPx" in focus

# Equivalent 4px margins and 8px swatch radii stay tied to design tokens;
# cell geometry and the existing full-card mouse target remain untouched.
assert "anchors.margins: CortetsuDesign.spacingUnit" in launcher
assert "radius: CortetsuDesign.radiusSmall" in launcher
assert "anchors.fill: parent" in launcher and "acceptedButtons:" in launcher

print("PASS: Launcher and Dashboard share semantic typography and density roles")
