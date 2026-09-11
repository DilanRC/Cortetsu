#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MODULES = REPO / "cortetsu/modules"

spec = importlib.util.spec_from_file_location(
    "bottom_hub_target",
    REPO / "cortetsu/bin/check-bottom-hub-target.py",
)
assert spec and spec.loader
bottom_hub_target = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bottom_hub_target)

from wire_sad_shell import ensure_or_member, ensure_statement


def base_content() -> str:
    return '''StyledWindow {
    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        screenState.overview = false;
        panels.popouts.close();
    }

    WlrLayershell.layer: screenState.overview ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: screenState.overview || screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: screenState.overview ? null : (hasFullscreen ? emptyRegion : regions)

    HyprlandFocusGrab {
        active: {
            if (s.overview)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.overview = false;
            panels.popouts.hasCurrent = false;
        }
    }

    StyledRect {
        opacity: root.screenState.overview ? 0.58 : (root.screenState.clipboard ? 0.48 : 0)
    }
}
'''


def wire_flag(texts: dict[str, str], flag: str) -> None:
    ensure_statement(
        texts,
        "content",
        "    onHasFullscreenChanged: {",
        "\n        panels.popouts.close();",
        f"        screenState.{flag} = false;",
    )
    ensure_or_member(
        texts,
        "content",
        "WlrLayershell.layer: screenState.overview",
        " ? WlrLayer.Overlay",
        f"screenState.{flag}",
    )
    ensure_or_member(
        texts,
        "content",
        "WlrLayershell.keyboardFocus: screenState.overview",
        " || screenState.launcher",
        f"screenState.{flag}",
    )
    ensure_or_member(
        texts,
        "content",
        "mask: screenState.overview",
        " ? null",
        f"screenState.{flag}",
    )
    ensure_or_member(
        texts,
        "content",
        "if (s.overview",
        ")\n                return true;",
        f"s.{flag}",
    )
    ensure_statement(
        texts,
        "content",
        "        onCleared: {",
        "\n            panels.popouts.hasCurrent = false;",
        f"            root.screenState.{flag} = false;",
    )


def screen_state(flags: tuple[str, ...]) -> str:
    return "Item {\n" + "".join(f"    property bool {flag}\n" for flag in flags) + "}\n"


def validate_content(text: str, flags: tuple[str, ...]) -> bool:
    with tempfile.TemporaryDirectory(prefix="retained-overlay-") as td:
        root = Path(td)
        (root / "components").mkdir(parents=True)
        (root / "components/ScreenState.qml").write_text(screen_state(flags), encoding="utf-8")
        return bottom_hub_target.check_content_window(root, text)


def main() -> None:
    texts = {"content": base_content()}
    for flag in ("clipboard", "hardware", "displayManager", "wallpaperManager"):
        wire_flag(texts, flag)

    expected_flags = ("overview", "clipboard", "hardware", "displayManager", "wallpaperManager")
    if not validate_content(texts["content"], expected_flags):
        raise SystemExit("FAIL: sequential retained overlay wiring did not satisfy BottomHub invariants")
    print("PASS sequential-composition")

    before = texts["content"]
    wire_flag(texts, "clipboard")
    wire_flag(texts, "hardware")
    if texts["content"] != before:
        raise SystemExit("FAIL: re-running Clipboard/Hardware wiring changed an already-composed ContentWindow")
    print("PASS composed-idempotency")

    # A later Display member must survive re-running the older installers.
    for needle in (
        "screenState.displayManager",
        "root.screenState.displayManager = false;",
        "screenState.wallpaperManager",
        "root.screenState.wallpaperManager = false;",
    ):
        if needle not in texts["content"]:
            raise SystemExit(f"FAIL: retained Display member lost after idempotent wiring: {needle}")
    print("PASS later-overlay-preserved")

    policy = (MODULES / "OverlayPolicy.js").read_text(encoding="utf-8")
    wrapper = (MODULES / "wallpaper/Wrapper.qml").read_text(encoding="utf-8")
    controller = (MODULES / "WallpaperController.qml").read_text(encoding="utf-8")
    for flag in ("launcher", "session", "dashboard", "utilities", "sidebar", "overview", "clipboard", "hardware", "displayManager"):
        assert flag in policy, flag
    assert "function closeForWallpaper" in policy and "function hasCompetingPanel" in policy
    assert "globalOtherOverlayOpen" in wrapper
    assert "for (const candidate of CortetsuScreens.screens)" in wrapper
    assert "onGlobalOtherOverlayOpenChanged" in wrapper
    assert "closeCompetingPanels();" in wrapper
    assert "CortetsuShortcut" in controller and "OverlayPolicy.closeForWallpaper" in controller
    print("PASS direct-shortcut-and-two-monitor-exclusivity")

    for relative, flag in (
        ("overview/Wrapper.qml", "overview"),
        ("clipboard/Wrapper.qml", "clipboard"),
        ("hardware/Wrapper.qml", "hardware"),
        ("display/Wrapper.qml", "displayManager"),
        ("wallpaper/Wrapper.qml", "wallpaperManager"),
        ("calendar/Wrapper.qml", "calendar"),
    ):
        wrapper_text = (MODULES / relative).read_text(encoding="utf-8")
        assert f"screenState?.cortetsuState?.{flag}" in wrapper_text, relative
    launcher_list = (MODULES / "launcher/ContentList.qml").read_text(encoding="utf-8")
    assert launcher_list.count("root.screenState?.launcher ?? false") == 2
    null_safe = {
        "launcher/Wrapper.qml": ("screenState?.launcher ?? false", "screenState?.dashboard"),
        "osd/Wrapper.qml": ("screenState?.osd", "root.screenState && !content.hovered"),
        "session/Wrapper.qml": ("screenState?.session === true",),
        "dashboard/Wrapper.qml": ("screenState?.dashboard === true",),
        "sidebar/Wrapper.qml": ("screenState?.sidebar ?? false",),
        "utilities/Wrapper.qml": ("screenState?.utilities ?? false", "screenState?.session ?? false"),
        "wallpaper/Wrapper.qml": ("screenState?.cortetsuState",),
    }
    for relative, markers in null_safe.items():
        wrapper_text = (MODULES / relative).read_text(encoding="utf-8")
        assert all(marker in wrapper_text for marker in markers), relative
    print("PASS null-safe retained, launcher and drawer initialization")

    print("Retained overlay wiring tests: OK")


if __name__ == "__main__":
    main()
