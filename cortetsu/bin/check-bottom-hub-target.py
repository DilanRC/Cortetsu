#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def has_all(text: str, needles: tuple[str, ...]) -> bool:
    return all(needle in text for needle in needles)


def line_starting(text: str, prefix: str) -> str | None:
    prefix = prefix.strip()
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            return stripped
    return None


def block_between(text: str, start: str, end: str) -> str | None:
    start_pos = text.find(start)
    if start_pos < 0:
        return None
    end_pos = text.find(end, start_pos + len(start))
    if end_pos < 0:
        return None
    return text[start_pos:end_pos]


def qml_block(text: str, component: str, object_id: str) -> str:
    start = text.find(f"    {component} {{")
    while start >= 0:
        brace = text.find("{", start)
        depth = 0
        for index in range(brace, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    block = text[start:index + 1]
                    if f"id: {object_id}" in block:
                        return block
                    start = text.find(f"    {component} {{", index + 1)
                    break
        else:
            break
    return ""


def retained_overlay_flags(root: Path) -> tuple[str, ...]:
    """Return retained Cortetsu overlays that are actually wired in ScreenState.

    ContentWindow is intentionally a shared native surface. Clipboard, Hardware
    Center and Display Manager extend the same overview focus/layer/mask chains.
    A BottomHub check must preserve those members instead of demanding the
    byte-for-byte base overview expression.
    """
    screen_path = root / "components/ScreenState.qml"
    if not screen_path.is_file():
        return ("overview",)

    screen = screen_path.read_text(encoding="utf-8")
    flags = ["overview"]
    for flag in ("clipboard", "hardware", "displayManager"):
        if f"property bool {flag}" in screen:
            flags.append(flag)
    return tuple(flags)


def check_shell(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        "settings.watchFiles: false",
        "    BottomHub {}",
        "    OverviewController {}",
    )) and "    CustomDock {}" not in text


def check_screen_state(root: Path, text: str) -> bool:
    del root
    return "property bool overview" in text


def check_shortcuts(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        '"customDock", "launcher"',
        "const open = !(screenState.sidebar || screenState.utilities);",
        "screenState.sidebar = open;",
        "screenState.utilities = open;",
    ))


def check_content_window(root: Path, text: str) -> bool:
    flags = retained_overlay_flags(root)

    layer = line_starting(text, "WlrLayershell.layer:")
    keyboard = line_starting(text, "WlrLayershell.keyboardFocus:")
    mask = line_starting(text, "mask:")
    focus_active = block_between(text, "HyprlandFocusGrab {", "windows: [root]")
    cleared = block_between(text, "onCleared: {", "panels.popouts.hasCurrent = false;")
    fullscreen = block_between(text, "onHasFullscreenChanged: {", "panels.popouts.close();")

    if not all((layer, keyboard, mask, focus_active, cleared, fullscreen)):
        return False

    if "WlrLayer.Overlay" not in layer:
        return False
    if "WlrKeyboardFocus.OnDemand" not in keyboard:
        return False
    if "screenState.launcher" not in keyboard or "screenState.session" not in keyboard:
        return False
    if "? null" not in mask or "hasFullscreen ? emptyRegion : regions" not in mask:
        return False
    if "return true;" not in focus_active:
        return False

    for flag in flags:
        if f"screenState.{flag}" not in layer:
            return False
        if f"screenState.{flag}" not in keyboard:
            return False
        if f"screenState.{flag}" not in mask:
            return False
        if f"s.{flag}" not in focus_active:
            return False
        if f"screenState.{flag} = false;" not in fullscreen:
            return False
        if f"root.screenState.{flag} = false;" not in cleared:
            return False

    if "opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity" not in text:
        return False
    if "clipboard" in flags and "root.screenState.clipboard ? 0.48" not in text:
        return False

    return True


def check_panels(root: Path, text: str) -> bool:
    del root
    launcher = qml_block(text, "Launcher.Wrapper", "launcher")
    utilities = qml_block(text, "Utilities.Wrapper", "utilities")
    sidebar = qml_block(text, "Sidebar.Wrapper", "sidebar")
    session = qml_block(text, "Item", "sessionWrapper")
    return has_all(text, (
        "import qs.modules.overview as Overview",
        "readonly property alias overview: overview",
        "Overview.Wrapper {",
    )) and has_all(launcher, (
        "anchors.horizontalCenter: parent.horizontalCenter",
        "anchors.bottom: parent.bottom",
    )) and "anchors.top: notifications.bottom" not in launcher \
        and "sidebar: sidebar" not in utilities \
        and has_all(sidebar, (
            "anchors.bottom: parent.bottom",
            "anchors.right: root.screenState.utilities ? utilities.left : parent.right",
            "anchors.rightMargin: root.screenState.utilities ? Tokens.padding.medium : 0",
        )) \
        and "sidebar.width" not in session


def check_regions(root: Path, text: str) -> bool:
    del root
    utilities = qml_block(text, "R", "utilitiesRegion")
    # Older target files do not name the utilities R block. Keep a structural
    # fallback: the upstream override pins it to the visible bottom edge and
    # must be absent so component R follows panel.y instead.
    utilities_follows_panel = "panel: root.panels.utilities\n        y: root.win.height - height" not in text
    return has_all(text, (
        "y: root.win.height - height - panel.dockOffset",
        "width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width",
        "panel: root.panels.sidebar",
        "x: root.win.width - width\n        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness",
    )) and utilities_follows_panel


def check_sidebar(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        'objectName: "cortetsuBottomNotificationCenter"',
        "readonly property bool shouldBeActive: screenState.sidebar",
        "anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale",
        "implicitWidth: Math.min(520, parent.width - 16)",
        "implicitHeight: Math.min(430, parent.height * 0.55)",
        "anchors.fill: parent",
    )) and "anchors.rightMargin:" not in text and "screenState.sidebar && Config.sidebar.enabled" not in text


def check_popout_wrapper(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        "property bool bottomAttached",
        "property real bottomOffset: 54",
        "property real bottomRightMargin: 4",
        "property real bottomAnchorCenter: -1",
        "bottomAttached = false;",
        "onHasCurrentChanged:",
    ))


def check_popout_clip(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        "content.bottomAttached",
        "content.bottomAnchorCenter >= 0",
        "content.bottomAnchorCenter - content.nonAnimWidth / 2",
        "parent.width - content.nonAnimWidth - content.bottomRightMargin",
        "parent.height - content.nonAnimHeight - content.bottomOffset",
    )) and "Behavior on x" not in text and "Behavior on y" not in text


def check_interactions(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        "function insidePanel(panel: Item, x: real, y: real): bool",
        "popouts.bottomAttached",
        "insidePanel(panels.popoutsWrapper, x, y)",
        "const showSidebar = false;",
        "if (false && Config.sidebar.showOnHover)",
    )) and "const showUtilities =" not in text


def check_utilities(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        "readonly property bool shouldBeActive: screenState.utilities",
        "anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale",
        "implicitWidth: Math.min(Tokens.sizes.utilities.width, parent.width - 16)",
    )) and "Sidebar.Wrapper" not in text and "screenState.sidebar" not in text


def check_bar(root: Path, text: str) -> bool:
    del root
    return has_all(text, (
        "readonly property bool disabled: true",
        "readonly property int clampedWidth: 0",
        "readonly property int exclusiveZone: 0",
        "readonly property bool shouldBeVisible: false",
        "visible: false",
        "implicitWidth: 0",
    ))


CHECKS = {
    "shell.qml": check_shell,
    "components/ScreenState.qml": check_screen_state,
    "modules/Shortcuts.qml": check_shortcuts,
    "modules/drawers/ContentWindow.qml": check_content_window,
    "modules/drawers/Panels.qml": check_panels,
    "modules/drawers/Regions.qml": check_regions,
    "modules/sidebar/Wrapper.qml": check_sidebar,
    "modules/bar/BarWrapper.qml": check_bar,
    "modules/bar/popouts/Wrapper.qml": check_popout_wrapper,
    "modules/bar/popouts/ClipWrapper.qml": check_popout_clip,
    "modules/drawers/Interactions.qml": check_interactions,
    "modules/utilities/Wrapper.qml": check_utilities,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Valida estado semántico final de BottomHub")
    parser.add_argument("root", type=Path)
    parser.add_argument("rel")
    args = parser.parse_args()

    check = CHECKS.get(args.rel)
    if check is None:
        raise SystemExit(2)

    root = args.root.resolve()
    path = root / args.rel
    if not path.is_file():
        raise SystemExit(1)

    text = path.read_text(encoding="utf-8")
    raise SystemExit(0 if check(root, text) else 1)


if __name__ == "__main__":
    main()
