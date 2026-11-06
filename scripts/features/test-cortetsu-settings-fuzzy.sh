#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$root/cortetsu/modules/settings/sections/LauncherSection.qml" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
controls = {
    "fuzzyApplications": "useFuzzyApps",
    "fuzzyActions": "useFuzzyActions",
    "fuzzySchemes": "useFuzzySchemes",
    "fuzzyVariants": "useFuzzyVariants",
    "fuzzyWallpapers": "useFuzzyWallpapers",
}
for object_name, setting in controls.items():
    match = re.search(
        rf'SettingToggleRow\s*\{{(?:(?!SettingToggleRow).)*?objectName:\s*"{object_name}"(?:(?!SettingToggleRow).)*?\n\s*\}}',
        source,
        re.S,
    )
    assert match, f"missing independent control: {object_name}"
    block = match.group(0)
    assert f"checked: CortetsuConfig.{setting}" in block, object_name
    assert re.search(
        rf"onToggled:\s*value\s*=>\s*\{{\s*CortetsuConfig\.{setting}\s*=\s*value;\s*CortetsuConfig\.save\(\);\s*\}}",
        block,
    ), f"{object_name} is not persisted independently"
print("PASS: launcher fuzzy-search settings have independent persisted owners")
PY
