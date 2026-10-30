from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
typography = (ROOT / "cortetsu/modules/CortetsuTypography.js").read_text(encoding="utf-8")
dashboard = "\n".join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "cortetsu/modules/dashboard").glob("Dash*.qml")))
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

import re

zones = dashboard + focus + (ROOT / "cortetsu/modules/dashboard/Today.qml").read_text(encoding="utf-8")

# The dashboard speaks a short ink scale: the hero (the hour), the display
# (the temperature in Clima), the title (zone names, figures of gauges and
# rates) and the line (dates, notes, lyrics). Sizes come from that scale as
# is: no arithmetic that invents an in-between size.
for role in ("inkHeroPx", "inkDisplayPx", "inkTitlePx", "inkLinePx"):
    assert f"var {role} =" in typography, role
    assert f"CortetsuTypography.{role}" in zones, role
assert not re.search(r"Typography\.\w+Px\s*[*/+-]", zones), "a size computed from a role"
assert not re.search(r"textSize:\s*[\w.]*size\s*\*", zones), "a text size scaled from a box"

# Gauges are one size with one figure size; a zone cannot pass its own.
gauge = (ROOT / "cortetsu/modules/dashboard/DashGauge.qml").read_text(encoding="utf-8")
assert "readonly property real size:" in gauge
assert "textSize: CortetsuTypography.inkTitlePx" in gauge

# The notes beside the hour share the line size for their figure.
assert "textSize: CortetsuTypography.inkLinePx" in focus
weather = (ROOT / "cortetsu/modules/dashboard/DashWeatherSummary.qml").read_text(encoding="utf-8")
assert "DashInk { text: Weather.temp; textSize: CortetsuTypography.inkLinePx }" in weather

# Lyrics lines are all one size, so nothing reflows as the song moves on.
for name in ("DashLyrics.qml", "DashLyricLines.qml"):
    lyrics = (ROOT / f"cortetsu/modules/dashboard/{name}").read_text(encoding="utf-8")
    sizes = set(re.findall(r"textSize:\s*([^\n]+)", lyrics.split("delegate:")[1].split("MouseArea")[0] if "delegate:" in lyrics else lyrics))
    assert sizes == {"CortetsuTypography.inkLinePx"}, (name, sizes)

# Inicio centres the hour and shows several lyric lines, not one.
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
home = dash.split("id: homeZone")[1].split("Component {")[0]
assert "DashLyricLines" in home and "Lyrics.currentLine" not in home
assert home.count("Layout.alignment: Qt.AlignHCenter") >= 2

# Equivalent 4px margins and 8px swatch radii stay tied to design tokens;
# cell geometry and the existing full-card mouse target remain untouched.
assert "anchors.margins: CortetsuDesign.spacingUnit" in launcher
assert "radius: CortetsuDesign.radiusSmall" in launcher
assert "anchors.fill: parent" in launcher and "acceptedButtons:" in launcher

print("PASS: Launcher and Dashboard share semantic typography; the dashboard keeps one ink scale")
