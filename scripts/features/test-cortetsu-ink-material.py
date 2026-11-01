#!/usr/bin/env python3
"""The ink material and the type families have one source, so a theme changes every surface.

ui.toml [material] -> CortetsuDesign.material* -> CortetsuInkPanel, and every
surface reaches the material only through CortetsuInkPanel (directly, or
through CortetsuPopupSurface for popouts). A surface that paints its own
wash or grain, or hard-codes a strength, would stop following the theme.
"""
import re
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QML = ROOT / "cortetsu"
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")

keys = ("ground_alpha", "wash_alpha", "popup_wash_alpha", "grain", "popup_grain", "hairline_alpha")
ui = tomllib.loads(read("dotfiles/home/.config/cortetsu/ui.toml"))
defaults = read("cortetsu/theme/CortetsuDesignDefaults.js")
design = read("cortetsu/theme/CortetsuDesign.qml")
for key in keys:
    token = "material" + "".join(part.title() for part in key.split("_"))
    assert key in ui["material"], key
    assert f"var {token} = {ui['material'][key]}" in defaults, token
    assert f"readonly property real {token}: Defaults.{token}" in design, token

panel = read("cortetsu/components/CortetsuInkPanel.qml")
for token in ("materialGroundAlpha", "materialWashAlpha", "materialGrain", "materialHairlineAlpha"):
    assert f"CortetsuDesign.{token}" in panel, token
assert not re.search(r"property real (groundAlpha|washAlpha|grain):\s*[\d.]", panel), "a literal strength"

popup = read("cortetsu/components/CortetsuPopupSurface.qml")
assert "CortetsuInkPanel {" in popup
assert "CortetsuDesign.materialPopupWashAlpha" in popup and "CortetsuDesign.materialPopupGrain" in popup

# Nobody else paints the wash, and grain strengths come from the tokens.
owners = {"components/CortetsuInkPanel.qml", "components/CortetsuGrain.qml"}
for path in QML.rglob("*.qml"):
    rel = str(path.relative_to(QML))
    if rel in owners or "/tests/" in f"/{rel}":
        continue
    text = path.read_text(encoding="utf-8")
    assert "RadialGradient" not in text, f"{rel} paints its own wash"
    for strength in re.findall(r"CortetsuGrain\s*{[^}]*strength:\s*([^;}\n]+)", text):
        assert strength.strip().startswith("CortetsuDesign.material") or rel == "components/CortetsuHanko.qml", (rel, strength)

# The ink surfaces and every popout reach the material through the shared pieces.
for rel in ("modules/dashboard/Dash.qml", "modules/SessionHost.qml", "modules/SettingsHost.qml",
            "modules/hardware/Content.qml", "modules/keyboards/Content.qml", "modules/display/Editor.qml",
            "modules/clipboard/Content.qml", "modules/wallpaper/Content.qml", "modules/calendar/Content.qml",
            "modules/drawers/ContentWindow.qml"):
    assert "CortetsuInkPanel" in (QML / rel).read_text(encoding="utf-8"), rel
for rel in ("modules/osd/Content.qml", "modules/launcher/Content.qml", "modules/utilities/Content.qml",
            "modules/bar/popouts/CortetsuAudioPopup.qml", "modules/bar/popouts/CortetsuTrayMenu.qml",
            "modules/bar/popouts/CortetsuNetworkPopup.qml", "modules/bar/popouts/CortetsuBluetoothPopup.qml",
            "modules/bar/popouts/CortetsuBatteryPopup.qml", "modules/polkit/PolkitDialog.qml",
            "modules/prompt/SecretPrompt.qml", "modules/screenshare/ScreenSharePanel.qml"):
    assert "CortetsuPopupSurface" in (QML / rel).read_text(encoding="utf-8"), rel

# Type families are theme tokens too: ui.toml [typography] -> CortetsuDesign.font*.
for key, token in (("ui_family", "fontUi"), ("ink_family", "fontInk"), ("kanji_family", "fontKanji")):
    assert f'var {token} = "{ui["typography"][key]}"' in defaults, token
    assert f"readonly property string {token}: Defaults.{token}" in design, token
typography = read("cortetsu/modules/CortetsuTypography.js")
assert not re.search(r"var (uiFamily|inkFamily|kanjiFamily)\b", typography), "a text family outside the theme"
for path in QML.rglob("*.qml"):
    rel = str(path.relative_to(QML))
    if "/tests/" in f"/{rel}":
        continue
    for family in re.findall(r'font\.family:\s*"([^"]+)"', path.read_text(encoding="utf-8")):
        assert family == "Material Symbols Rounded", f"{rel} hard-codes the font {family}"

# Inside the Calendar the day agenda and the pomodoro are ink wells, not flat
# container blocks laid over the ink.
calendar = read("cortetsu/modules/calendar/Content.qml")
pomodoro = read("cortetsu/modules/calendar/PomodoroCard.qml")
assert "CortetsuInkWell {" in calendar and "colorSurfaceHigh" not in calendar
assert pomodoro.count("CortetsuInkWell {") == 1 and "SecondaryContainer" not in pomodoro

# The transparency setting reaches the ink through its one painter.
assert "materialGroundAlpha * (CortetsuConfig.transparencyEnabled ? 0.78 : 1)" in panel

print("PASS: the ink material has one source (ui.toml) and one painter (CortetsuInkPanel)")
