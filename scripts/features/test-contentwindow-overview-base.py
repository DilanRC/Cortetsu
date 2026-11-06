#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[2]
REFERENCE = REPO / "tests/reference/python-runtime"
NORMALIZER = REFERENCE / "cortetsu/bin/normalize-contentwindow-overview-24.py"
CHECKER = REFERENCE / "cortetsu/bin/check-bottom-hub-target.py"
sys.path.insert(0, str(REFERENCE / "scripts/features"))

from wire_sad_shell import ensure_or_member, ensure_statement


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"No pude cargar {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


normalizer = load_module("contentwindow_overview_normalizer", NORMALIZER)
checker = load_module("contentwindow_overview_checker", CHECKER)

PARTIAL = '''StyledWindow {
    id: root

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: hasFullscreen ? emptyRegion : regions

    HyprlandFocusGrab {
        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled) || (s.utilities && conf.utilities.enabled))
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.utilities = false;
            root.screenState.dashboard = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim
    }
}
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-contentwindow-overview-") as td:
        root = Path(td)
        content = root / "modules/drawers/ContentWindow.qml"
        screen = root / "components/ScreenState.qml"
        content.parent.mkdir(parents=True)
        screen.parent.mkdir(parents=True)
        content.write_text(PARTIAL, encoding="utf-8")
        screen.write_text("Item {\n    property bool overview\n}\n", encoding="utf-8")

        if not normalizer.normalize(root):
            raise SystemExit("FAIL partial-overview-recovery: normalizer reported no change")
        text = content.read_text(encoding="utf-8")
        if not checker.check_content_window(root, text):
            raise SystemExit("FAIL partial-overview-recovery: target checker rejected normalized content")
        if normalizer.normalize(root):
            raise SystemExit("FAIL partial-overview-recovery: second pass was not idempotent")
        print("PASS partial-overview-recovery")

        texts = {"content": text}
        ensure_statement(
            texts, "content",
            "    onHasFullscreenChanged: {", "\n        panels.popouts.close();",
            "        screenState.clipboard = false;",
        )
        ensure_or_member(
            texts, "content",
            "WlrLayershell.layer: screenState.overview", " ? WlrLayer.Overlay",
            "screenState.clipboard",
        )
        ensure_or_member(
            texts, "content",
            "WlrLayershell.keyboardFocus: screenState.overview", " || screenState.launcher",
            "screenState.clipboard",
        )
        ensure_or_member(
            texts, "content",
            "mask: screenState.overview", " ? null",
            "screenState.clipboard",
        )
        ensure_or_member(
            texts, "content",
            "if (s.overview", ")\n                return true;",
            "s.clipboard",
        )
        ensure_statement(
            texts, "content",
            "        onCleared: {", "\n            panels.popouts.hasCurrent = false;",
            "            root.screenState.clipboard = false;",
        )
        for marker in (
            "screenState.clipboard",
            "s.clipboard",
            "root.screenState.clipboard = false;",
        ):
            if marker not in texts["content"]:
                raise SystemExit(f"FAIL clipboard-after-overview: missing {marker}")
        print("PASS clipboard-after-overview")

    print("ContentWindow Overview base tests: OK")


if __name__ == "__main__":
    main()
