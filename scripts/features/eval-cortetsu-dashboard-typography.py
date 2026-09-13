from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
files = {
    "typography": ROOT / "cortetsu/modules/CortetsuTypography.js",
    "datetime": ROOT / "cortetsu/modules/dashboard/dash/DateTime.qml",
    "media": ROOT / "cortetsu/modules/dashboard/dash/Media.qml",
    "dashboard": ROOT / "cortetsu/modules/dashboard/Dash.qml",
    "focus": ROOT / "cortetsu/modules/dashboard/Focus.qml",
    "launcher": ROOT / "cortetsu/modules/launcher/AppList.qml",
}
source = {name: path.read_text(encoding="utf-8") for name, path in files.items()}

checks = {
    "display aliases exist": all(
        f"var {alias} =" in source["typography"]
        for alias in ("displaySmallPx", "displayMediumPx", "displayClockPx", "displayLargePx", "displayHeroPx")
    ),
    "dashboard uses shared display roles": all(
        token in source["dashboard"]
        for token in (
            "CortetsuTypography.displayClockPx",
            "CortetsuTypography.displayHeroPx",
            "CortetsuTypography.displayLargePx",
            "CortetsuTypography.iconFeaturePx",
        )
    ),
    "dashboard sub-surfaces use first-party primitives": all(
        token in source[name]
        for name in ("datetime", "media")
        for token in ("CortetsuText", "CortetsuTypography")
    ) and "CortetsuIcon" in source["media"],
    "launcher density uses design tokens": all(
        token in source["launcher"]
        for token in ("CortetsuDesign.spacingUnit", "CortetsuDesign.radiusSmall")
    ),
    "launcher interaction bounds remain present": all(
        token in source["launcher"]
        for token in ("anchors.fill: parent", "acceptedButtons:", "root.screenState.launcher = false")
    ),
    "raw large font declarations are removed": all(
        "font.pixelSize:" not in source[name] for name in ("datetime", "media")
    ),
}

passed = sum(checks.values())
for label, result in checks.items():
    print(f"{'PASS' if result else 'FAIL'} {label}")
assert passed == len(checks), f"Dashboard typography eval: {passed}/{len(checks)}"
print(f"Dashboard typography eval: {passed}/{len(checks)}")
