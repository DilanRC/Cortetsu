#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "cortetsu/contracts/wall-utility.json"


def read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    assert isinstance(value, dict), path
    return value


contract = read_json(CONTRACT_PATH)
with (ROOT / "cortetsu.toml").open("rb") as handle:
    manifest = tomllib.load(handle)
with (ROOT / "dotfiles/home/.config/cortetsu/ui.toml").open("rb") as handle:
    ui = tomllib.load(handle)

assert contract["schema"] == 1
assert contract["id"] == "wall-utility-bcde"
assert contract["product"] == "Cortetsu"
assert contract["direction"] == {
    "wallpaperAware": True,
    "utilityFirst": True,
    "workbenchSettings": True,
    "configurableModularity": True,
}
assert contract["entrypoint"] == "modules/wallpaper/Content.qml"
assert contract["host"] == "modules/RetainedSurfacesHost.qml"
assert contract["wrapper"] == "modules/wallpaper/Wrapper.qml"
assert contract["configSource"] == "dotfiles/home/.config/cortetsu/ui.toml"
assert manifest["product"]["wall_utility"]["contract"] == "cortetsu/contracts/wall-utility.json"
assert manifest["product"]["wall_utility"]["config"] == contract["configSource"]
assert set(contract["states"]) == {"idle", "selected", "applying", "applied", "failed"}
assert contract["screenPolicy"] == {
    "surfaceOwnership": "monitor-local",
    "shortcutTarget": "active-monitor",
    "selectionTarget": "clicked-monitor",
}
assert contract["applyLifecycle"]["acknowledgement"].endswith("cortetsu/wallpaper/path.txt")
assert contract["applyLifecycle"]["cosmicPolicy"] == "success-pulse-only"

for relative in (contract["entrypoint"], contract["host"], contract["wrapper"], contract["configSource"]):
    assert (ROOT / ("cortetsu" if relative.startswith("modules/") else "") / relative).is_file(), relative

wall_utility = ui["wall_utility"]
for key, expected in {
    "surface_radius": "shape.radius_surface",
    "panel_motion": "motion.panel_ms",
    "orbit_motion": "motion.standard_ms",
    "crossfade_motion": "motion.standard_ms",
    "orbit_top_gap": "spacing.section",
    "orbit_bottom_gap": "spacing.section",
    "footer_gap": "spacing.compact",
    "category_gap": "spacing.compact",
}.items():
    assert wall_utility[key] == expected, key

build = (ROOT / "cortetsu/bin/build-runtime.sh").read_text(encoding="utf-8")
controller = (ROOT / "cortetsu/modules/WallpaperController.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
host = (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
service = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
content = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
wrapper = (ROOT / "cortetsu/modules/wallpaper/Wrapper.qml").read_text(encoding="utf-8")

assert 'WALL_UTILITY_CONTRACT="$REPO/cortetsu/contracts/wall-utility.json"' in build
assert 'install -m 0644 "$WALL_UTILITY_CONTRACT" "$STAGING/wall-utility.json"' in build
assert "wall-utility.json" in build
assert "pragma Singleton" in controller
assert "function open(screen): void" in controller
assert "function openActive(): void" in controller
assert "CortetsuShellState.forScreen(target)?.cortetsuState" in controller
assert "function toggle(): void { anyOpen() ? closeAll() : openActive(); }" in controller
assert "function open(): void { root.openActive(); }" in controller
assert "WallpaperController.open(screen);" in hub
assert "candidate === screen" not in hub
assert "CortetsuShellState.forScreen(modelData)" in host
assert "Wallpaper.Wrapper" in host
assert '? "applying"' in service and ': "idle"' in service
assert '"cortetsu-wallpaper-select", target' in service
assert 'cortetsu/wallpaper/path.txt' in service
assert "onWallpaperApplySucceeded" in content
assert "cosmicPulse" in content
assert "wallUtility" in content + wrapper
assert "CortetsuDesign.wallUtilityPanelMotionMs" in wrapper
assert "CortetsuDesign.wallUtilityOrbitTopGap" in content
assert "CortetsuDesign.wallUtilityOrbitBottomGap" in content

parser = argparse.ArgumentParser()
parser.add_argument("--runtime", type=Path)
args = parser.parse_args()
if args.runtime:
    installed = read_json(args.runtime / "wall-utility.json")
    assert installed == contract
    print(f"PASS: installed Wall Utility contract matches {args.runtime}")
else:
    print("PASS: Wall Utility BCDE source contract and ownership are valid")
