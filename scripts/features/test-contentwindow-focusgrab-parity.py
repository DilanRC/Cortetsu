#!/usr/bin/env python3
"""Regression test for the overlay-host focus/exclusivity gap.

The retained-overlay contract (overview, calendar, clipboard, hardware,
displayManager, wallpaperManager) is supposed to close uniformly from three
triggers: fullscreen change, Escape, and HyprlandFocusGrab.onCleared
(click-outside). Before this fix, the ContentWindow adapter patch closed all
six flags on the first two triggers via CortetsuScreenState.closeRetainedOverlays(),
but onCleared only reset `overview` via setRetained("overview", false) --
clicking outside Calendar/Clipboard/Hardware/DisplayManager/WallpaperManager
did not close them.

This test reads the first-party ContentWindow source and asserts it closes
every retained overlay uniformly from all three triggers.
"""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
AFTER_BASE_PATCH = '''StyledWindow {
    id: root

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        screenState.overview = false;
        screenState.calendar = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: screenState.overview ? WlrLayer.Overlay : ((fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top)
    WlrLayershell.keyboardFocus: screenState.overview || screenState.calendar || screenState.clipboard || screenState.hardware || screenState.displayManager || screenState.wallpaperManager || screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: (screenState.overview || screenState.calendar) ? null : (hasFullscreen ? emptyRegion : regions)

    anchors.top: true
    anchors.bottom: true

    Shortcut {
        sequence: "Escape"
        enabled: focusGrab.active
        onActivated: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.utilities = false;
            root.screenState.dashboard = false;
            root.screenState.overview = false;
            root.screenState.calendar = false;
            root.screenState.clipboard = false;
            root.screenState.hardware = false;
            root.screenState.displayManager = false;
            root.screenState.wallpaperManager = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if (s.overview || s.calendar || s.clipboard || s.hardware || s.displayManager || s.wallpaperManager)
                return true;
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
            root.screenState.overview = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: root.screenState.overview ? 0.58 : ((root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0)
        color: Colours.palette.m3scrim

        Behavior on opacity {
            NumberAnimation {}
        }
    }
}
'''


def block_between(text: str, start: str, end: str) -> str:
    start_pos = text.find(start)
    assert start_pos >= 0, f"missing block start: {start}"
    end_pos = text.find(end, start_pos)
    assert end_pos >= 0, f"missing block end: {end}"
    return text[start_pos:end_pos]


def main() -> None:
    text = (REPO / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")

    assert 'import "../bar" as Bar' in text
    assert "Bar.BarWrapper {" in text
    assert "\n        BarWrapper {" not in text
    print("PASS bar-import-boundary")

    fullscreen = block_between(text, "onHasFullscreenChanged: {", "panels.popouts.close();")
    escape = block_between(text, 'sequence: "Escape"', "        }\n    }")
    focus_grab = block_between(text, "active: {", "        windows: [root]")
    cleared = block_between(text, "onCleared: {", "bar.closeTray();")

    assert "cortetsuState?.closeRetainedOverlays();" in fullscreen, "onHasFullscreenChanged must close every retained overlay"
    assert "cortetsuState?.closeRetainedOverlays();" in escape, "Escape must close every retained overlay"
    assert "cortetsuState?.closeRetainedOverlays();" in cleared, (
            "FAIL regression: HyprlandFocusGrab.onCleared (click-outside) must close every "
            "retained overlay via closeRetainedOverlays(), matching Escape and fullscreen-change. "
            "Found instead:\n" + cleared
        )
    assert 'setRetained("overview", false)' not in cleared, (
            "FAIL regression: onCleared regressed to partially closing only 'overview' -- "
            "click-outside would no longer close calendar/clipboard/hardware/displayManager/"
            "wallpaperManager overlays"
        )
    print("PASS onCleared-closes-all-retained-overlays")

    assert "screenState?.cortetsuState?.requiresFullInputMask" in text
    assert "screenState?.cortetsuState?.requiresWindowKeyboardFocus" in text
    assert "WlrKeyboardFocus.Exclusive" in text
    assert "if (s.cortetsuState?.retainedOverlayOpen)\n                return false;" in focus_grab, (
        "retained surfaces own their separate overlay input and must not be cleared "
        "by the drawers focus grab"
    )
    assert "if (panels.popouts.isDetached || panels.popouts.currentName === \"wirelesspassword\")" in focus_grab
    assert "root.screenState?.cortetsuState?.overview ? 0.58" in text
    print("PASS input-mask-focus-scrim-still-wired")

    print("ContentWindow focus-grab parity tests: OK")


if __name__ == "__main__":
    main()
