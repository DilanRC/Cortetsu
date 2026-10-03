#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


LAYER_UPSTREAM = (
    "    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) "
    "|| (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top"
)
LAYER_TARGET = (
    "    WlrLayershell.layer: screenState.overview ? WlrLayer.Overlay : "
    "((fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) "
    "|| (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top)"
)
KEYBOARD_UPSTREAM = (
    "    WlrLayershell.keyboardFocus: screenState.launcher || screenState.session "
    "? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None"
)
KEYBOARD_TARGET = (
    "    WlrLayershell.keyboardFocus: screenState.overview || screenState.launcher || "
    "screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None"
)
MASK_UPSTREAM = "    mask: hasFullscreen ? emptyRegion : regions"
MASK_TARGET = "    mask: screenState.overview ? null : (hasFullscreen ? emptyRegion : regions)"
SCRIM_UPSTREAM = (
    "        opacity: (root.screenState.session && Config.session.enabled) || "
    "panels.popouts.detachedMode !== \"\" ? 0.5 : 0"
)
SCRIM_TARGET = (
    "        opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity : "
    "((root.screenState.session && Config.session.enabled) || "
    "panels.popouts.detachedMode !== \"\" ? 0.5 : 0)"
)


def replace_recognized_line(text: str, old: str, new: str, marker: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"ERROR: ContentWindow.qml no está en un estado 2.4 reconocido para {marker}; "
            f"esperaba 1 línea base y encontré {count}"
        )
    return text.replace(old, new, 1)


def ensure_before(text: str, anchor: str, tail: str, statement: str, label: str) -> str:
    start = text.find(anchor)
    if start < 0:
        raise SystemExit(f"ERROR: falta anchor {label}")
    end = text.find(tail, start + len(anchor))
    if end < 0:
        raise SystemExit(f"ERROR: falta tail {label}")
    span = text[start:end]
    if statement.strip() in span:
        return text
    return text[:end] + statement + text[end:]


def normalize(root: Path) -> bool:
    path = root / "modules/drawers/ContentWindow.qml"
    if not path.is_file():
        raise SystemExit(f"ERROR: no existe {path}")

    before = path.read_text(encoding="utf-8")
    required = (
        "StyledWindow {",
        "    onHasFullscreenChanged: {",
        "    HyprlandFocusGrab {",
        "        onCleared: {",
        "        panels.popouts.close();",
        "            panels.popouts.hasCurrent = false;",
    )
    missing = [marker for marker in required if marker not in before]
    if missing:
        raise SystemExit(
            "ERROR: ContentWindow.qml no parece Caelestia 2.4 compatible; faltan: "
            + ", ".join(missing)
        )

    after = before
    after = ensure_before(
        after,
        "    onHasFullscreenChanged: {",
        "        panels.popouts.close();",
        "        screenState.overview = false;\n",
        "onHasFullscreenChanged/overview",
    )
    after = replace_recognized_line(after, LAYER_UPSTREAM, LAYER_TARGET, "screenState.overview ? WlrLayer.Overlay")
    after = replace_recognized_line(after, KEYBOARD_UPSTREAM, KEYBOARD_TARGET, "WlrLayershell.keyboardFocus: screenState.overview")
    after = replace_recognized_line(after, MASK_UPSTREAM, MASK_TARGET, "mask: screenState.overview ? null")

    focus_anchor = "            const conf = root.contentItem.Config;\n"
    focus_block_start = after.find("    HyprlandFocusGrab {")
    focus_block_end = after.find("        windows: [root]", focus_block_start)
    if focus_block_start < 0 or focus_block_end < 0:
        raise SystemExit("ERROR: no pude delimitar HyprlandFocusGrab")
    focus_block = after[focus_block_start:focus_block_end]
    focus_stmt = "            if (s.overview)\n                return true;\n"
    if "if (s.overview" not in focus_block:
        marker_pos = after.find(focus_anchor, focus_block_start, focus_block_end)
        if marker_pos < 0:
            raise SystemExit("ERROR: no encontré const conf dentro de HyprlandFocusGrab")
        insert = marker_pos + len(focus_anchor)
        after = after[:insert] + focus_stmt + after[insert:]

    after = ensure_before(
        after,
        "        onCleared: {",
        "            panels.popouts.hasCurrent = false;",
        "            root.screenState.overview = false;\n",
        "onCleared/overview",
    )
    after = replace_recognized_line(
        after,
        SCRIM_UPSTREAM,
        SCRIM_TARGET,
        "opacity: root.screenState.overview ? CortetsuDesign.scrimOpacity",
    )

    if after == before:
        return False
    path.write_text(after, encoding="utf-8")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Restaura las invariantes base de Overview en ContentWindow de Caelestia 2.4"
    )
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    changed = normalize(args.root.resolve())
    print("NORMALIZED modules/drawers/ContentWindow.qml" if changed else "ALREADY modules/drawers/ContentWindow.qml")


if __name__ == "__main__":
    main()
