#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def write_if_changed(path: Path, before: str, after: str) -> bool:
    if before == after:
        return False
    path.write_text(after, encoding="utf-8")
    return True


def qml_block(text: str, component: str, object_id: str) -> tuple[int, int]:
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
                    end = index + 1
                    block = text[start:end]
                    if f"id: {object_id}" in block:
                        return start, end
                    start = text.find(f"    {component} {{", end)
                    break
        else:
            break
    raise SystemExit(f"ERROR: no encontré el bloque {component} con id {object_id}")


def migrate_shell(root: Path) -> bool:
    path = root / "shell.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before.replace("    CustomDock {}\n", "    BottomHub {}\n")
    return write_if_changed(path, before, after)


def migrate_shortcuts(root: Path) -> bool:
    path = root / "modules/Shortcuts.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before.replace(
        "            const screenState = ShellState.forActive();\n"
        "            screenState.sidebar = !screenState.sidebar;\n",
        "            const screenState = ShellState.forActive();\n"
        "            const open = !(screenState.sidebar || screenState.utilities);\n"
        "            screenState.sidebar = open;\n"
        "            screenState.utilities = open;\n",
        1,
    )
    return write_if_changed(path, before, after)


def migrate_panels(root: Path) -> bool:
    path = root / "modules/drawers/Panels.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    if "import qs.modules.overview as Overview" not in before:
        return False

    after = before
    launcher_start, launcher_end = qml_block(after, "Launcher.Wrapper", "launcher")
    launcher = after[launcher_start:launcher_end]
    lines = [
        line for line in launcher.splitlines()
        if not line.strip().startswith("anchors.")
    ]
    lines[-1:-1] = [
        "        anchors.horizontalCenter: parent.horizontalCenter",
        "        anchors.bottom: parent.bottom",
    ]
    after = after[:launcher_start] + "\n".join(lines) + after[launcher_end:]

    utility_start, utility_end = qml_block(after, "Utilities.Wrapper", "utilities")
    utility = after[utility_start:utility_end]
    utility = utility.replace("        sidebar: sidebar\n", "")
    after = after[:utility_start] + utility + after[utility_end:]

    sidebar_start, sidebar_end = qml_block(after, "Sidebar.Wrapper", "sidebar")
    sidebar = after[sidebar_start:sidebar_end]
    sidebar_lines = [
        line for line in sidebar.splitlines()
        if not line.strip().startswith("anchors.")
    ]
    sidebar_lines[-1:-1] = [
        "        anchors.bottom: parent.bottom",
        "        anchors.right: root.screenState.utilities ? utilities.left : parent.right",
        "        anchors.rightMargin: root.screenState.utilities ? Tokens.padding.medium : 0",
    ]
    after = after[:sidebar_start] + "\n".join(sidebar_lines) + after[sidebar_end:]

    osd_start, osd_end = qml_block(after, "Item", "osdWrapper")
    osd = after[osd_start:osd_end]
    osd = osd.replace("clip: sidebar.visible || session.visible", "clip: session.visible")
    osd = osd.replace("sidebarOrSessionVisible: sidebar.visible || session.visible", "sidebarOrSessionVisible: session.visible")
    after = after[:osd_start] + osd + after[osd_end:]

    session_start, session_end = qml_block(after, "Item", "sessionWrapper")
    session = after[session_start:session_end]
    session = session.replace(
        "anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)",
        "anchors.rightMargin: 0",
    ).replace("clip: sidebar.visible", "clip: false")
    after = after[:session_start] + session + after[session_end:]

    toast_start, toast_end = qml_block(after, "Toasts.Toasts", "toasts")
    toast = after[toast_start:toast_end]
    toast = toast.replace(
        "anchors.bottom: sidebar.visible ? parent.bottom : utilities.top",
        "anchors.bottom: utilities.top",
    ).replace(
        "anchors.bottom: sidebar.visible ? sidebar.top : utilities.top",
        "anchors.bottom: utilities.top",
    ).replace("anchors.right: sidebar.left", "anchors.right: parent.right")
    after = after[:toast_start] + toast + after[toast_end:]

    return write_if_changed(path, before, after)


def migrate_sidebar(root: Path) -> bool:
    path = root / "modules/sidebar/Wrapper.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before.replace('objectName: "cortetsuNativeSidebar"', 'objectName: "cortetsuBottomNotificationCenter"')
    if "objectName:" not in after:
        after = after.replace("    id: root\n", '    id: root\n    objectName: "cortetsuBottomNotificationCenter"\n', 1)
    after = after.replace(
        "readonly property bool shouldBeActive: screenState.sidebar && Config.sidebar.enabled",
        "readonly property bool shouldBeActive: screenState.sidebar",
    )
    if "readonly property bool shouldBeActive:" not in after:
        after = after.replace(
            '    objectName: "cortetsuBottomNotificationCenter"\n',
            '    objectName: "cortetsuBottomNotificationCenter"\n\n'
            '    readonly property bool shouldBeActive: screenState.sidebar\n',
            1,
        )

    start = after.index("    visible: offsetScale < 1")
    end = after.index("    opacity: 1 - offsetScale", start)
    geometry = (
        "    visible: offsetScale < 1\n"
        "    anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale\n\n"
        "    implicitWidth: Math.min(520, parent.width - 16)\n"
        "    implicitHeight: Math.min(430, parent.height * 0.55)\n"
    )
    after = after[:start] + geometry + after[end:]

    loader_start, loader_end = qml_block(after, "Loader", "content")
    loader = after[loader_start:loader_end]
    anchor_start = loader.index("        anchors.")
    active_start = loader.index("        active:", anchor_start)
    loader = loader[:anchor_start] + "        anchors.fill: parent\n\n" + loader[active_start:]
    loader = loader.replace(
        "implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins",
        "implicitWidth: root.implicitWidth",
    )
    after = after[:loader_start] + loader + after[loader_end:]
    return write_if_changed(path, before, after)


def migrate_utilities(root: Path) -> bool:
    path = root / "modules/utilities/Wrapper.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before.replace("import qs.modules.sidebar as Sidebar\n", "")
    after = after.replace("    required property Sidebar.Wrapper sidebar\n", "")
    after = after.replace("    property real horizontalStretch\n", "")
    after = after.replace(
        "screenState.sidebar || (screenState.utilities && Config.utilities.enabled && !(screenState.session && Config.session.enabled))",
        "screenState.utilities && Config.utilities.enabled && !(screenState.session && Config.session.enabled)",
    )
    after = after.replace("    property real sidebarLerp\n", "")

    if "    states: State {" in after:
        state_start = after.index("    states: State {")
        behavior = after.index("    Behavior on offsetScale {", state_start)
        after = after[:state_start] + after[behavior:]

    start = after.index("    visible: offsetScale < 1")
    end = after.index("    opacity: 1 - offsetScale", start)
    geometry = (
        "    visible: offsetScale < 1\n"
        "    anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale\n"
        "    implicitHeight: content.implicitHeight + totalPadding\n"
        "    implicitWidth: Math.min(Tokens.sizes.utilities.width, parent.width - 16)\n"
    )
    after = after[:start] + geometry + after[end:]
    return write_if_changed(path, before, after)


def migrate_bar(root: Path) -> bool:
    path = root / "modules/bar/BarWrapper.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before
    replacements = {
        "readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)": "readonly property bool disabled: true",
        "readonly property int clampedWidth: Math.max(Config.border.minThickness, implicitWidth)": "readonly property int clampedWidth: 0",
        "readonly property int exclusiveZone: !disabled && (Config.bar.persistent || screenState.bar) ? contentWidth : Config.border.thickness": "readonly property int exclusiveZone: 0",
        "readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || screenState.bar || isHovered)": "readonly property bool shouldBeVisible: false",
        "visible: width > Config.border.thickness": "visible: false",
        "implicitWidth: fullscreen ? 0 : Config.border.thickness": "implicitWidth: 0",
    }
    for old, new in replacements.items():
        after = after.replace(old, new)
    return write_if_changed(path, before, after)


def migrate_popout_clip(root: Path) -> bool:
    path = root / "modules/bar/popouts/ClipWrapper.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before.replace(
        "        : content.bottomAttached\n"
        "            ? parent.width - content.nonAnimWidth - content.bottomRightMargin\n"
        "            : 0",
        "        : content.bottomAttached\n"
        "            ? content.bottomAnchorCenter >= 0\n"
        "                ? Math.max(8, Math.min(parent.width - content.nonAnimWidth - 8, content.bottomAnchorCenter - content.nonAnimWidth / 2))\n"
        "                : parent.width - content.nonAnimWidth - content.bottomRightMargin\n"
        "            : 0",
        1,
    )
    for marker in ("    Behavior on x {\n", "    Behavior on y {\n"):
        start = after.find(marker)
        if start < 0:
            continue
        brace = after.index("{", start)
        depth = 0
        for index in range(brace, len(after)):
            if after[index] == "{":
                depth += 1
            elif after[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    if end < len(after) and after[end] == "\n":
                        end += 1
                    after = after[:start] + after[end:]
                    break
    return write_if_changed(path, before, after)


def migrate_popout_wrapper(root: Path) -> bool:
    path = root / "modules/bar/popouts/Wrapper.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before
    if "property real bottomAnchorCenter:" not in after:
        after = after.replace(
            "    property real bottomRightMargin: 4\n",
            "    property real bottomRightMargin: 4\n"
            "    property real bottomAnchorCenter: -1\n",
            1,
        )
    after = after.replace(
        "    function detach(mode: string): void {\n"
        "        bottomAttached = false;\n"
        "        setAnims(true);",
        "    function detach(mode: string): void {\n"
        "        bottomAttached = false;\n"
        "        bottomAnchorCenter = -1;\n"
        "        setAnims(true);",
        1,
    )
    after = after.replace(
        "        detachedMode = \"\";\n"
        "        bottomAttached = false;\n"
        "    }\n\n"
        "    onHasCurrentChanged: {\n"
        "        if (!hasCurrent)\n"
        "            bottomAttached = false;\n"
        "    }",
        "        detachedMode = \"\";\n"
        "        bottomAttached = false;\n"
        "        bottomAnchorCenter = -1;\n"
        "    }\n\n"
        "    onHasCurrentChanged: {\n"
        "        if (!hasCurrent) {\n"
        "            bottomAttached = false;\n"
        "            bottomAnchorCenter = -1;\n"
        "        }\n"
        "    }",
        1,
    )
    return write_if_changed(path, before, after)


def migrate_interactions(root: Path) -> bool:
    path = root / "modules/drawers/Interactions.qml"
    if not path.is_file():
        return False
    before = path.read_text(encoding="utf-8")
    after = before.replace(
        "if (Config.sidebar.showOnHover)",
        "if (false && Config.sidebar.showOnHover)",
    ).replace(
        "if (Config.sidebar.showOnHover && !pressed)",
        "if (false && Config.sidebar.showOnHover && !pressed)",
    ).replace(
        "const showSidebar = pressed && dragStart.x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x);",
        "const showSidebar = false;",
    ).replace(
        "if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)",
        "if (false && pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)",
    )
    return write_if_changed(path, before, after)


def main() -> None:
    parser = argparse.ArgumentParser(description="Migra Cortetsu al Bottom Hub sin sidebar visual")
    parser.add_argument("root", type=Path, help="raíz de Caelestia (real o copia temporal)")
    args = parser.parse_args()
    root = args.root.resolve()

    changed = []
    for name, fn in (
        ("shell.qml", migrate_shell),
        ("modules/Shortcuts.qml", migrate_shortcuts),
        ("modules/drawers/Panels.qml", migrate_panels),
        ("modules/sidebar/Wrapper.qml", migrate_sidebar),
        ("modules/utilities/Wrapper.qml", migrate_utilities),
        ("modules/bar/BarWrapper.qml", migrate_bar),
        ("modules/bar/popouts/Wrapper.qml", migrate_popout_wrapper),
        ("modules/bar/popouts/ClipWrapper.qml", migrate_popout_clip),
        ("modules/drawers/Interactions.qml", migrate_interactions),
    ):
        if fn(root):
            changed.append(name)

    print("MIGRATED " + ", ".join(changed) if changed else "MIGRATION no-op")


if __name__ == "__main__":
    main()
