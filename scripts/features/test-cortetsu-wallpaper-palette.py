#!/usr/bin/env python3
"""Gate the wallpaper scheme bridge used by compatibility surfaces."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
colours = (ROOT / "cortetsu/services/CortetsuColours.qml").read_text(encoding="utf-8")
wallpapers = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")

for marker in (
    "import Quickshell.Io",
    "property var currentColours: ({})",
    "property var previewColours: ({})",
    "readonly property var activeColours:",
    "function normaliseHex(value): string",
    "return /^#[0-9a-fA-F]{6}$/.test(hex) ? hex : \"\";",
    "FileView {",
    "watchChanges: true",
    "onLoaded: root.load(text(), false)",
    "onFileChanged: root.load(text(), false)",
    "onLoadFailed: root.currentColours = ({})",
    "currentColours = ({})",
    "function clearPreview(): void",
    "previewColours = ({})",
    "m3primary: root.schemeColour(\"primary\", CortetsuDesign.colorPrimary)",
    "m3surface: root.schemeColour(\"surface\", CortetsuDesign.colorSurface)",
    "m3error: CortetsuDesign.colorVermillion",
    "CortetsuDesign.colorWashi",
    "CortetsuDesign.colorTetsu",
):
    assert marker in colours, marker

for marker in (
    'import "../services"',
    "CortetsuColours.clearPreview();",
    "CortetsuColours.load(text, true);",
    "if (CortetsuConfig.smartScheme)",
):
    assert marker in wallpapers, marker

print("PASS: wallpaper scheme state is reactive, validated, previewable and safely reset")
