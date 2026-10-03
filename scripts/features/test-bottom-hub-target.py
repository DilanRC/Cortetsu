#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CHECKER_PATH = REPO / "cortetsu/bin/check-bottom-hub-target.py"
MIGRATOR_PATH = REPO / "cortetsu/bin/migrate-bottom-hub-from-main.py"
REL = "modules/drawers/ContentWindow.qml"

spec = importlib.util.spec_from_file_location("bottom_hub_target_checker", CHECKER_PATH)
if spec is None or spec.loader is None:
    raise SystemExit(f"No pude cargar {CHECKER_PATH}")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

migrator_spec = importlib.util.spec_from_file_location("bottom_hub_migrator", MIGRATOR_PATH)
if migrator_spec is None or migrator_spec.loader is None:
    raise SystemExit(f"No pude cargar {MIGRATOR_PATH}")
migrator = importlib.util.module_from_spec(migrator_spec)
migrator_spec.loader.exec_module(migrator)


def screen_state(flags: tuple[str, ...]) -> str:
    return "Item {\n" + "".join(f"    property bool {flag}\n" for flag in flags) + "}\n"


def content_window(
    flags: tuple[str, ...],
    *,
    omit_from: str | None = None,
    clipboard_scrim: bool = True,
) -> str:
    screen_flags = [f"screenState.{flag}" for flag in flags]
    s_flags = [f"s.{flag}" for flag in flags]

    def members(values: list[str], context: str) -> str:
        filtered = values[:-1] if omit_from == context else values
        return " || ".join(filtered)

    fullscreen_flags = flags[:-1] if omit_from == "fullscreen" else flags
    cleared_flags = flags[:-1] if omit_from == "cleared" else flags
    fullscreen_lines = "".join(
        f"        screenState.{flag} = false;\n" for flag in fullscreen_flags
    )
    cleared_lines = "".join(
        f"            root.screenState.{flag} = false;\n" for flag in cleared_flags
    )

    opacity = "opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity : 0"
    if "clipboard" in flags and clipboard_scrim:
        opacity = (
            "opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity : "
            "(root.screenState.clipboard ? 0.48 : 0)"
        )

    return (
        "StyledWindow {\n"
        "    onHasFullscreenChanged: {\n"
        f"{fullscreen_lines}"
        "        panels.popouts.close();\n"
        "    }\n\n"
        f"    WlrLayershell.layer: {members(screen_flags, 'layer')} ? WlrLayer.Overlay : WlrLayer.Top\n"
        f"    WlrLayershell.keyboardFocus: {members(screen_flags, 'keyboard')} || screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None\n"
        f"    mask: {members(screen_flags, 'mask')} ? null : (hasFullscreen ? emptyRegion : regions)\n\n"
        "    HyprlandFocusGrab {\n"
        "        active: {\n"
        f"            if ({members(s_flags, 'active')})\n"
        "                return true;\n"
        "            return false;\n"
        "        }\n"
        "        windows: [root]\n"
        "        onCleared: {\n"
        f"{cleared_lines}"
        "            panels.popouts.hasCurrent = false;\n"
        "        }\n"
        "    }\n\n"
        "    StyledRect {\n"
        f"        {opacity}\n"
        "    }\n"
        "}\n"
    )


def run_case(
    name: str,
    flags: tuple[str, ...],
    *,
    expected: bool,
    omit_from: str | None = None,
    clipboard_scrim: bool = True,
) -> None:
    with tempfile.TemporaryDirectory(prefix="bottom-hub-target-") as td:
        root = Path(td)
        (root / "components").mkdir(parents=True)
        (root / "modules/drawers").mkdir(parents=True)
        (root / "components/ScreenState.qml").write_text(
            screen_state(flags), encoding="utf-8"
        )
        text = content_window(
            flags,
            omit_from=omit_from,
            clipboard_scrim=clipboard_scrim,
        )
        (root / REL).write_text(text, encoding="utf-8")
        actual = checker.check_content_window(root, text)
        if actual != expected:
            raise SystemExit(
                f"FAIL {name}: expected={expected} actual={actual}"
            )
        print(f"PASS {name}")


def run_corrupt_runtime_migration() -> None:
    with tempfile.TemporaryDirectory(prefix="bottom-hub-panels-") as td:
        root = Path(td)
        panels = root / "modules/drawers/Panels.qml"
        panels.parent.mkdir(parents=True)
        panels.write_text(
            "import qs.modules.overview as Overview\n"
            "Item {\n"
            "    id: root\n"
            "    readonly property alias overview: overview\n"
            "    Item {\n"
            "        id: osdWrapper\n"
            "        clip: sidebar.visible || session.visible\n"
            "        Osd.Wrapper {\n"
            "            sidebarOrSessionVisible: sidebar.visible || session.visible\n"
            "        }\n"
            "    }\n"
            "    Item {\n"
            "        id: sessionWrapper\n"
            "        anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)\n"
            "        clip: sidebar.visible\n"
            "    }\n"
            "    Overview.Wrapper {\n"
            "        id: overview\n"
            "    }\n"
            "    Launcher.Wrapper {\n"
            "        id: launcher\n"
            "        screen: root.screen\n"
            "        anchors.top: notifications.bottom\n"
            "        anchors.bottom: utilities.top\n"
            "        anchors.right: parent.right\n"
            "    }\n"
            "    Toasts.Toasts {\n"
            "        id: toasts\n"
            "        anchors.bottom: utilities.top\n"
            "        anchors.right: parent.right\n"
            "    }\n"
            "    Utilities.Wrapper {\n"
            "        id: utilities\n"
            "        screenState: root.screenState\n"
            "        sidebar: sidebar\n"
            "        popouts: popoutsWrapper.content\n"
            "    }\n"
            "    Sidebar.Wrapper {\n"
            "        id: sidebar\n"
            "        anchors.horizontalCenter: parent.horizontalCenter\n"
            "        anchors.bottom: parent.bottom\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        assert migrator.migrate_panels(root) is True
        text = panels.read_text(encoding="utf-8")
        if not checker.check_panels(root, text):
            raise SystemExit("FAIL panels-tolerant-migration")
        print("PASS corrupt-panels-scoped-migration")


def run_sidebar_migration() -> None:
    with tempfile.TemporaryDirectory(prefix="bottom-hub-sidebar-") as td:
        root = Path(td)
        sidebar = root / "modules/sidebar/Wrapper.qml"
        sidebar.parent.mkdir(parents=True)
        sidebar.write_text(
            "Item {\n"
            "    id: root\n"
            "    objectName: \"cortetsuNativeSidebar\"\n"
            "    visible: offsetScale < 1\n"
            "    anchors.rightMargin: (-implicitWidth - 5) * offsetScale\n"
            "    implicitWidth: Tokens.sizes.sidebar.width\n"
            "    opacity: 1 - offsetScale\n"
            "    Loader {\n"
            "        id: content\n"
            "        anchors.top: parent.top\n"
            "        anchors.bottom: parent.bottom\n"
            "        anchors.left: parent.left\n"
            "        active: root.visible\n"
            "        sourceComponent: Content {\n"
            "            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins\n"
            "        }\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        assert migrator.migrate_sidebar(root) is True
        text = sidebar.read_text(encoding="utf-8")
        if not checker.check_sidebar(root, text):
            raise SystemExit("FAIL bottom-notification-migration")
        print("PASS bottom-notification-migration")


def run_motion_and_bar_migration() -> None:
    with tempfile.TemporaryDirectory(prefix="bottom-hub-motion-") as td:
        root = Path(td)
        bar = root / "modules/bar/BarWrapper.qml"
        clip = root / "modules/bar/popouts/ClipWrapper.qml"
        clip.parent.mkdir(parents=True)
        bar.write_text(
            "Item {\n"
            "    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)\n"
            "    readonly property int clampedWidth: Math.max(Config.border.minThickness, implicitWidth)\n"
            "    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || screenState.bar) ? contentWidth : Config.border.thickness\n"
            "    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || screenState.bar || isHovered)\n"
            "    visible: width > Config.border.thickness\n"
            "    implicitWidth: fullscreen ? 0 : Config.border.thickness\n"
            "}\n",
            encoding="utf-8",
        )
        clip.write_text(
            "Item {\n"
            "    content.bottomAttached\n"
            "    content.bottomAnchorCenter >= 0\n"
            "    content.bottomAnchorCenter - content.nonAnimWidth / 2\n"
            "    parent.width - content.nonAnimWidth - content.bottomRightMargin\n"
            "    parent.height - content.nonAnimHeight - content.bottomOffset\n"
            "    Behavior on x {\n"
            "        Anim {}\n"
            "    }\n"
            "    Behavior on y {\n"
            "        Anim {}\n"
            "    }\n"
            "    Wrapper {}\n"
            "}\n",
            encoding="utf-8",
        )
        assert migrator.migrate_bar(root) is True
        assert migrator.migrate_popout_clip(root) is True
        if not checker.check_bar(root, bar.read_text(encoding="utf-8")):
            raise SystemExit("FAIL visual-bar-removal")
        if not checker.check_popout_clip(root, clip.read_text(encoding="utf-8")):
            raise SystemExit("FAIL horizontal-motion-removal")
        print("PASS visual-bar-and-popup-motion-removal")


def run_incremental_bottom_hub_upgrade() -> None:
    with tempfile.TemporaryDirectory(prefix="bottom-hub-incremental-") as td:
        root = Path(td)
        shortcuts = root / "modules/Shortcuts.qml"
        wrapper = root / "modules/bar/popouts/Wrapper.qml"
        clip = root / "modules/bar/popouts/ClipWrapper.qml"
        wrapper.parent.mkdir(parents=True)
        shortcuts.parent.mkdir(parents=True, exist_ok=True)

        shortcuts.write_text(
            "Item {\n"
            "    CustomShortcut {\n"
            "        name: \"launcher\"\n"
            "        Quickshell.execDetached([\"qs\", \"-c\", \"caelestia\", \"ipc\", \"call\", \"customDock\", \"launcher\"]);\n"
            "    }\n"
            "    CustomShortcut {\n"
            "        name: \"sidebar\"\n"
            "        onPressed: {\n"
            "            const screenState = ShellState.forActive();\n"
            "            screenState.sidebar = !screenState.sidebar;\n"
            "        }\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        wrapper.write_text(
            "Item {\n"
            "    property bool bottomAttached\n"
            "    property real bottomOffset: 54\n"
            "    property real bottomRightMargin: 4\n"
            "    function detach(mode: string): void {\n"
            "        bottomAttached = false;\n"
            "        setAnims(true);\n"
            "    }\n"
            "    function close(): void {\n"
            "        hasCurrent = false;\n"
            "        detachedMode = \"\";\n"
            "        bottomAttached = false;\n"
            "    }\n\n"
            "    onHasCurrentChanged: {\n"
            "        if (!hasCurrent)\n"
            "            bottomAttached = false;\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        clip.write_text(
            "Item {\n"
            "    x: content.isDetached\n"
            "        ? (parent.width - content.nonAnimWidth) / 2\n"
            "        : content.bottomAttached\n"
            "            ? parent.width - content.nonAnimWidth - content.bottomRightMargin\n"
            "            : 0\n"
            "    content.bottomAttached\n"
            "    parent.height - content.nonAnimHeight - content.bottomOffset\n"
            "    Behavior on y {\n"
            "        Anim {}\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )

        assert migrator.migrate_shortcuts(root) is True
        assert migrator.migrate_popout_wrapper(root) is True
        assert migrator.migrate_popout_clip(root) is True
        assert checker.check_shortcuts(root, shortcuts.read_text(encoding="utf-8"))
        assert checker.check_popout_wrapper(root, wrapper.read_text(encoding="utf-8"))
        assert checker.check_popout_clip(root, clip.read_text(encoding="utf-8"))
        assert migrator.migrate_shortcuts(root) is False
        assert migrator.migrate_popout_wrapper(root) is False
        assert migrator.migrate_popout_clip(root) is False
        print("PASS incremental-bottom-hub-upgrade")


def main() -> None:
    run_case("overview-base", ("overview",), expected=True)
    run_case(
        "layered-retained-overlays",
        ("overview", "clipboard", "hardware", "displayManager"),
        expected=True,
    )
    run_case(
        "missing-display-from-mask",
        ("overview", "clipboard", "hardware", "displayManager"),
        expected=False,
        omit_from="mask",
    )
    run_case(
        "missing-display-from-cleared",
        ("overview", "clipboard", "hardware", "displayManager"),
        expected=False,
        omit_from="cleared",
    )
    run_case(
        "clipboard-scrim-regression",
        ("overview", "clipboard", "hardware", "displayManager"),
        expected=False,
        clipboard_scrim=False,
    )
    run_corrupt_runtime_migration()
    run_sidebar_migration()
    run_motion_and_bar_migration()
    run_incremental_bottom_hub_upgrade()
    print("BottomHub semantic target tests: OK")


if __name__ == "__main__":
    main()
