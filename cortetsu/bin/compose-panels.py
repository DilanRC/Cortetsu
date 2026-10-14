#!/usr/bin/env python3
"""Compose Cortetsu-owned overlays into one staged Panels.qml."""
from __future__ import annotations

import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: compose-panels.py <runtime-root>")

root = Path(sys.argv[1])
path = root / "modules/drawers/Panels.qml"
if not path.is_file():
    raise SystemExit(f"missing Panels.qml: {path}")
text = path.read_text(encoding="utf-8")

required_imports = (
    'import "../../theme"',
    "import qs.modules.overview as Overview",
    "import qs.modules.clipboard as Clipboard",
    "import qs.modules.hardware as Hardware",
    "import qs.modules.display as Display",
    "import qs.modules.wallpaper as Wallpaper",
    "import qs.modules.calendar as Calendar",
)
lines = text.splitlines()
missing_imports = [line for line in required_imports if line not in lines]
if missing_imports:
    import_indexes = [index for index, line in enumerate(lines) if line.startswith("import ")]
    if not import_indexes:
        raise SystemExit("Panels.qml has no import block")
    insert_at = import_indexes[-1] + 1
    lines[insert_at:insert_at] = missing_imports
    text = "\n".join(lines) + "\n"

alias_anchor = "    readonly property alias overview: overview\n"
required_aliases = (
    "    readonly property alias clipboard: clipboard\n",
    "    readonly property alias hardware: hardware\n",
    "    readonly property alias displayManager: displayManager\n",
    "    readonly property alias wallpaperManager: wallpaperManager\n",
    "    readonly property alias calendar: calendar\n",
)
if alias_anchor not in text:
    raise SystemExit("missing overview alias anchor")
for alias in required_aliases:
    if alias not in text:
        text = text.replace(alias_anchor, alias_anchor + alias, 1)

wrapper_anchor = "    Dashboard.Wrapper {\n"
if wrapper_anchor not in text:
    raise SystemExit("missing Dashboard.Wrapper anchor")
wrappers = (
    (
        "id: clipboard",
        "    Clipboard.Wrapper {\n"
        "        id: clipboard\n"
        "        screen: root.screen\n"
        "        screenState: root.screenState\n"
        "        anchors.fill: parent\n"
        "    }\n\n",
    ),
    (
        "id: hardware",
        "    Hardware.Wrapper {\n"
        "        id: hardware\n"
        "        screen: root.screen\n"
        "        screenState: root.screenState\n"
        "        anchors.fill: parent\n"
        "    }\n\n",
    ),
    (
        "id: displayManager",
        "    Display.Wrapper {\n"
        "        id: displayManager\n"
        "        screen: root.screen\n"
        "        screenState: root.screenState\n"
        "        anchors.fill: parent\n"
        "    }\n\n",
    ),
    (
        "id: wallpaperManager",
        "    Wallpaper.Wrapper {\n"
        "        id: wallpaperManager\n"
        "        screen: root.screen\n"
        "        screenState: root.screenState\n"
        "        anchors.fill: parent\n"
        "    }\n\n",
    ),
    (
        "id: calendar",
        "    Calendar.Wrapper {\n"
        "        id: calendar\n"
        "        screenState: root.screenState\n"
        "        anchors.horizontalCenter: parent.horizontalCenter\n"
        "        anchors.bottom: parent.bottom\n"
        "        anchors.bottomMargin: bar.implicitHeight + CortetsuDesign.spacingStandard\n"
        "    }\n\n",
    ),
)
for marker, block in wrappers:
    if marker not in text:
        text = text.replace(wrapper_anchor, block + wrapper_anchor, 1)

text = text.replace("        sidebar: sidebar\n", "")
path.write_text(text, encoding="utf-8")

for required_import in required_imports:
    if text.count(required_import) != 1:
        raise SystemExit(f"invalid import count: {required_import}")
for marker in (
    "id: overview",
    "id: clipboard",
    "id: hardware",
    "id: displayManager",
    "id: wallpaperManager",
    "id: calendar",
):
    if text.count(marker) != 1:
        raise SystemExit(f"invalid composed marker count: {marker}")
print("PASS: unified Cortetsu panel composition")
