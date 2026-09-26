#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
contract = json.loads((ROOT / "cortetsu/contracts/wall-utility.json").read_text(encoding="utf-8"))
build = (ROOT / "cortetsu/bin/build-runtime.sh").read_text(encoding="utf-8")
controller = (ROOT / "cortetsu/modules/WallpaperController.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
display_controller = (ROOT / "cortetsu/modules/DisplayController.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
service = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
content = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
dashboard_host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dashboard = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")

checks = {
    "contract schema and identity": contract["schema"] == 1 and contract["id"] == "wall-utility-bcde",
    "BCDE direction": all(contract["direction"].values()),
    "explicit ownership": all(contract[key] for key in ("stateOwner", "screenOwner", "applyOwner")),
    "monitor-local policy": contract["screenPolicy"]["surfaceOwnership"] == "monitor-local",
    "screen-aware controller": "function open(screen): void" in controller and "function openActive(): void" in controller,
    "wallpaper IPC is available at startup": "readonly property var wallpaperController: WallpaperController" in shell
        and 'target: "wallpapermanager"' in controller,
    "display handoff preserves screen": "function open(screen): void" in display_controller
        and "CortetsuShellState.forScreen(target)?.cortetsuState" in display_controller,
    "BottomHub delegates open": "WallpaperController.open(screen);" in hub,
    "apply lifecycle ACK": 'cortetsu/wallpaper/path.txt' in service and '"cortetsu-wallpaper-select", target' in service,
    "Cosmic success pulse": "onWallpaperApplySucceeded" in content and "cosmicPulse" in content,
    "generation transport": 'install -m 0644 "$WALL_UTILITY_CONTRACT" "$STAGING/wall-utility.json"' in build,
    "dashboard modularity contract": contract["modularity"]["dashboard"]["host"] == "modules/DashboardHost.qml"
        and contract["modularity"]["dashboard"]["content"] == "modules/dashboard/Dash.qml"
        and "sourceComponent: weatherCard" in dashboard
        and "sourceComponent: mediaCard" in dashboard
        and "sourceComponent: systemSummary" in dashboard
        and "readonly property bool dashboardEnabled" in dashboard_host,
    "configuration authorities are explicit": contract["configSource"] == "dotfiles/home/.config/cortetsu/ui.toml"
        and contract["runtimePreferences"] == "XDG config file cortetsu/preferences.json",
    "workbench return handoff": 'SettingsController.select("wallpaper")' in content
        and "function returnToSettings(): void" in content,
}

passed = sum(checks.values())
for name, result in checks.items():
    print(f"{'PASS' if result else 'FAIL'}: {name}")
assert passed == len(checks), checks
print(f"Wall Utility BCDE eval: {passed}/{len(checks)}")
