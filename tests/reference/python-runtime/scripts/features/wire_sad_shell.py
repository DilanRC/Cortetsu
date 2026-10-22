#!/usr/bin/env python3
"""Canonical SAD shell wiring.

The retained runtime consists of Hardware Center and Display Manager. Gaming
Center and Cortetsu Updater were retired from the product and must not be
reintroduced by rebuilds.

Every run first removes legacy Gaming/Updater integration from an older live
tree, then idempotently ensures Display Manager is wired on top of Hardware.
The transform is staged before installation and fails loudly when the retained
Hardware anchors are missing.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path


class WiringError(RuntimeError):
    pass


def replace_once(texts: dict[str, str], key: str, old: str, new: str, marker: str) -> bool:
    if marker in texts[key]:
        return False
    if old not in texts[key]:
        raise WiringError(f"PREFLIGHT ERROR [{key}]: missing context for {marker!r}")
    texts[key] = texts[key].replace(old, new, 1)
    return True


def _find_span(text: str, anchor: str, tail: str, what: str) -> re.Match[str]:
    pattern = re.compile(re.escape(anchor) + r"(.*?)" + re.escape(tail), re.DOTALL)
    match = pattern.search(text)
    if not match:
        raise WiringError(f"PREFLIGHT ERROR: missing anchor/tail for {what!r}")
    return match


def ensure_or_member(texts: dict[str, str], key: str, anchor: str, tail: str, member: str) -> bool:
    text = texts[key]
    match = _find_span(text, anchor, tail, member)
    if member in match.group(1):
        return False
    insertion_point = match.start(1) + len(match.group(1))
    texts[key] = text[:insertion_point] + f" || {member}" + text[insertion_point:]
    return True


def ensure_statement(texts: dict[str, str], key: str, anchor: str, tail: str, statement: str) -> bool:
    text = texts[key]
    match = _find_span(text, anchor, tail, statement)
    if statement in match.group(1):
        return False
    insertion_point = match.start(1) + len(match.group(1))
    texts[key] = text[:insertion_point] + "\n" + statement + text[insertion_point:]
    return True


def insert_wrapper(texts: dict[str, str], flag: str, block: str, anchor: str = "    Dashboard.Wrapper {") -> bool:
    if f"id: {flag}" in texts["panels"]:
        return False
    if anchor not in texts["panels"]:
        raise WiringError(f"PREFLIGHT ERROR [panels]: missing anchor {anchor!r}")
    texts["panels"] = texts["panels"].replace(anchor, block + anchor, 1)
    return True


def insert_bind(texts: dict[str, str], bind: str, anchor: str, comment: str) -> bool:
    if bind in texts["user"]:
        return False
    if anchor not in texts["user"]:
        raise WiringError(f"PREFLIGHT ERROR [user]: missing bind anchor {anchor!r}")
    texts["user"] = texts["user"].replace(anchor, anchor + f"\n\n-- {comment}\n" + bind, 1)
    return True


def _remove_legacy_bind(text: str, key: str, target: str, comment: str) -> str:
    bind = f'''hl.bind(
    "{key}",
    hl.dsp.global("{target}")
)'''
    for block in (f"-- {comment}\n{bind}\n", f"-- {comment}\n{bind}", bind + "\n", bind):
        text = text.replace(block, "")
    return text


def retire_removed_centers(texts: dict[str, str]) -> bool:
    """Remove exactly the runtime integration owned by the retired centers."""
    before = dict(texts)

    for flag in ("gamingCenter", "updaterCenter"):
        texts["screen"] = re.sub(
            rf"(?m)^\s*property bool {flag}\s*\n", "", texts["screen"]
        )

    for controller in ("GamingController", "UpdaterController"):
        texts["shell"] = re.sub(
            rf"(?m)^\s*{controller} \{{\}}\s*\n", "", texts["shell"]
        )

    for module, alias, flag in (
        ("gaming", "Gaming", "gamingCenter"),
        ("updater", "Updater", "updaterCenter"),
    ):
        texts["panels"] = re.sub(
            rf"(?m)^\s*import qs\.modules\.{module} as {alias}\s*\n", "", texts["panels"]
        )
        texts["panels"] = re.sub(
            rf"(?m)^\s*readonly property alias {flag}: {flag}\s*\n", "", texts["panels"]
        )
        compact_block = (
            f"    {alias}.Wrapper {{\n"
            f"        id: {flag}\n"
            "        screen: root.screen\n"
            "        screenState: root.screenState\n"
            "        anchors.fill: parent\n"
            "    }\n\n"
        )
        spaced_block = (
            f"    {alias}.Wrapper {{\n"
            f"        id: {flag}\n\n"
            "        screen: root.screen\n"
            "        screenState: root.screenState\n\n"
            "        anchors.fill: parent\n"
            "    }\n\n"
        )
        texts["panels"] = texts["panels"].replace(compact_block, "")
        texts["panels"] = texts["panels"].replace(spaced_block, "")

    for flag in ("gamingCenter", "updaterCenter"):
        texts["content"] = re.sub(
            rf"(?m)^\s*(?:root\.)?screenState\.{flag}\s*=\s*false;\s*\n",
            "",
            texts["content"],
        )
        texts["content"] = texts["content"].replace(f" || screenState.{flag}", "")
        texts["content"] = texts["content"].replace(f"screenState.{flag} || ", "")
        texts["content"] = texts["content"].replace(f" || s.{flag}", "")
        texts["content"] = texts["content"].replace(f"s.{flag} || ", "")

    texts["user"] = _remove_legacy_bind(
        texts["user"], "SUPER + SHIFT + G", "cortetsu:gamingcenter", "Gaming Center QML nativo"
    )
    texts["user"] = _remove_legacy_bind(
        texts["user"], "SUPER + SHIFT + U", "cortetsu:updatercenter", "Cortetsu Updater QML nativo"
    )

    leftovers = {
        "screen": ("gamingCenter", "updaterCenter"),
        "shell": ("GamingController", "UpdaterController"),
        "panels": (
            "qs.modules.gaming", "qs.modules.updater", "gamingCenter", "updaterCenter",
            "Gaming.Wrapper", "Updater.Wrapper",
        ),
        "content": ("gamingCenter", "updaterCenter"),
        "user": ("cortetsu:gamingcenter", "cortetsu:updatercenter"),
    }
    for key, markers in leftovers.items():
        present = [marker for marker in markers if marker in texts[key]]
        if present:
            raise WiringError(
                f"RETIREMENT ERROR [{key}]: legacy Gaming/Updater marker(s) remain: "
                + ", ".join(present)
            )

    return any(before[key] != texts[key] for key in texts)


def _wire_display(texts: dict[str, str]) -> bool:
    changed = False
    changed |= replace_once(
        texts, "screen",
        "    property bool hardware\n    property bool dashboard",
        "    property bool hardware\n    property bool displayManager\n    property bool dashboard",
        "property bool displayManager",
    )
    changed |= replace_once(
        texts, "shell",
        "    HardwareController {}\n    BatteryMonitor {}",
        "    HardwareController {}\n    DisplayController {}\n    BatteryMonitor {}",
        "DisplayController {}",
    )
    changed |= replace_once(
        texts, "panels",
        "import qs.modules.hardware as Hardware\nimport qs.modules.notifications as Notifications",
        "import qs.modules.hardware as Hardware\nimport qs.modules.display as Display\nimport qs.modules.notifications as Notifications",
        "import qs.modules.display as Display",
    )
    changed |= replace_once(
        texts, "panels",
        "    readonly property alias hardware: hardware\n    readonly property alias dashboard: dashboard",
        "    readonly property alias hardware: hardware\n    readonly property alias displayManager: displayManager\n    readonly property alias dashboard: dashboard",
        "readonly property alias displayManager: displayManager",
    )
    changed |= insert_wrapper(
        texts,
        "displayManager",
        "    Display.Wrapper {\n        id: displayManager\n\n        screen: root.screen\n        screenState: root.screenState\n\n        anchors.fill: parent\n    }\n\n",
    )
    changed |= ensure_statement(
        texts, "content",
        "        screenState.hardware = false;", "\n        panels.popouts.close();",
        "        screenState.displayManager = false;",
    )
    changed |= ensure_or_member(
        texts, "content",
        "WlrLayershell.layer: screenState.overview || screenState.clipboard || screenState.hardware",
        " ? WlrLayer.Overlay", "screenState.displayManager",
    )
    changed |= ensure_or_member(
        texts, "content",
        "WlrLayershell.keyboardFocus: screenState.overview || screenState.clipboard || screenState.hardware",
        " || screenState.launcher", "screenState.displayManager",
    )
    changed |= ensure_or_member(
        texts, "content",
        "mask: screenState.overview || screenState.clipboard || screenState.hardware",
        " ? null", "screenState.displayManager",
    )
    changed |= ensure_or_member(
        texts, "content",
        "if (s.overview || s.clipboard || s.hardware", ")\n                return true;",
        "s.displayManager",
    )
    changed |= ensure_statement(
        texts, "content",
        "            root.screenState.hardware = false;", "\n            panels.popouts.hasCurrent = false;",
        "            root.screenState.displayManager = false;",
    )
    changed |= insert_bind(
        texts,
        'hl.bind(\n    "SUPER + SHIFT + O",\n    hl.dsp.global("cortetsu:displaymanager")\n)',
        'hl.bind(\n    "SUPER + H",\n    hl.dsp.global("cortetsu:hardware")\n)',
        "Display Manager QML nativo",
    )
    return changed


def _wire_wallpaper(texts: dict[str, str]) -> bool:
    """Add the native wallpaper manager to the existing drawer surface."""
    changed = False
    changed |= replace_once(
        texts, "screen",
        "    property bool hardware\n    property bool displayManager",
        "    property bool hardware\n    property bool displayManager\n    property bool wallpaperManager",
        "property bool wallpaperManager",
    )
    changed |= replace_once(
        texts, "shell",
        "    DisplayController {}\n    BatteryMonitor {}",
        "    DisplayController {}\n    WallpaperController {}\n    BatteryMonitor {}",
        "WallpaperController {}",
    )
    changed |= replace_once(
        texts, "panels",
        "import qs.modules.display as Display\nimport qs.modules.notifications as Notifications",
        "import qs.modules.display as Display\nimport qs.modules.wallpaper as Wallpaper\nimport qs.modules.notifications as Notifications",
        "import qs.modules.wallpaper as Wallpaper",
    )
    changed |= replace_once(
        texts, "panels",
        "    readonly property alias displayManager: displayManager\n    readonly property alias dashboard: dashboard",
        "    readonly property alias displayManager: displayManager\n    readonly property alias wallpaperManager: wallpaperManager\n    readonly property alias dashboard: dashboard",
        "readonly property alias wallpaperManager: wallpaperManager",
    )
    changed |= insert_wrapper(
        texts,
        "wallpaperManager",
        "    Wallpaper.Wrapper {\n        id: wallpaperManager\n\n        screen: root.screen\n        screenState: root.screenState\n\n        anchors.fill: parent\n    }\n\n",
    )
    changed |= ensure_statement(
        texts, "content",
        "        screenState.displayManager = false;", "\n        panels.popouts.close();",
        "        screenState.wallpaperManager = false;",
    )
    changed |= ensure_or_member(
        texts, "content",
        "WlrLayershell.layer: screenState.overview || screenState.clipboard || screenState.hardware",
        " ? WlrLayer.Overlay", "screenState.wallpaperManager",
    )
    changed |= ensure_or_member(
        texts, "content",
        "WlrLayershell.keyboardFocus: screenState.overview || screenState.clipboard || screenState.hardware",
        " || screenState.launcher", "screenState.wallpaperManager",
    )
    changed |= ensure_or_member(
        texts, "content",
        "mask: screenState.overview || screenState.clipboard || screenState.hardware",
        " ? null", "screenState.wallpaperManager",
    )
    changed |= ensure_or_member(
        texts, "content",
        "if (s.overview || s.clipboard || s.hardware", ")\n                return true;",
        "s.wallpaperManager",
    )
    changed |= ensure_statement(
        texts, "content",
        "            root.screenState.displayManager = false;", "\n            panels.popouts.hasCurrent = false;",
        "            root.screenState.wallpaperManager = false;",
    )
    changed |= insert_bind(
        texts,
        'hl.bind(\n    "SUPER + SHIFT + W",\n    hl.dsp.global("cortetsu:wallpapermanager")\n)',
        'hl.bind(\n    "SUPER + SHIFT + O",\n    hl.dsp.global("cortetsu:displaymanager")\n)',
        "Wallpaper Manager QML nativo",
    )
    return changed


FEATURES = {"display": _wire_display, "wallpaper": _wire_wallpaper}
ORDER = ("display", "wallpaper")


def load_texts(live: Path, usercfg: Path) -> dict[str, str]:
    paths = {
        "screen": live / "components/ScreenState.qml",
        "shell": live / "shell.qml",
        "panels": live / "modules/drawers/Panels.qml",
        "content": live / "modules/drawers/ContentWindow.qml",
        "user": usercfg,
    }
    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        raise WiringError("missing live file(s): " + ", ".join(missing))
    return {key: path.read_text(encoding="utf-8") for key, path in paths.items()}


def wire_all(
    live: Path,
    usercfg: Path,
    features: tuple[str, ...] = ORDER,
) -> tuple[dict[str, str], dict[str, bool]]:
    texts = load_texts(live, usercfg)
    changed: dict[str, bool] = {"retired": retire_removed_centers(texts)}
    for name in ORDER:
        if name in features:
            changed[name] = FEATURES[name](texts)
    return texts, changed


def write_staged(texts: dict[str, str], stage: Path) -> dict[str, Path]:
    out = {
        "screen": stage / "components/ScreenState.qml",
        "shell": stage / "shell.qml",
        "panels": stage / "modules/drawers/Panels.qml",
        "content": stage / "modules/drawers/ContentWindow.qml",
        "user": stage / "user-config/hypr-user.lua",
    }
    for key, path in out.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(texts[key], encoding="utf-8")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--live",
        default=os.environ.get(
            "CORTETSU_LIVE_ROOT",
            str(Path.home() / ".config/quickshell/cortetsu/current"),
        ),
    )
    parser.add_argument(
        "--usercfg",
        default=str(Path.home() / ".config/hypr/hypr-user.lua"),
    )
    parser.add_argument("--stage", required=True)
    parser.add_argument(
        "--features",
        default=",".join(ORDER),
        help="comma-separated subset of: " + ",".join(ORDER),
    )
    args = parser.parse_args()
    features = tuple(item for item in args.features.split(",") if item)
    unknown = [item for item in features if item not in FEATURES]
    if unknown:
        parser.error("unknown feature(s): " + ", ".join(unknown))
    try:
        texts, changed = wire_all(Path(args.live), Path(args.usercfg), features)
        write_staged(texts, Path(args.stage))
    except WiringError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    print(json.dumps({"ok": True, "changed": changed}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
