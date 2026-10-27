from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import surface_registry  # noqa: E402

repo = Path(__file__).resolve().parents[2]
state = (repo / "cortetsu/modules/CortetsuScreenState.qml").read_text(encoding="utf-8")
policy = (repo / "cortetsu/modules/CortetsuOverlayPolicy.js").read_text(encoding="utf-8")
panels_patch = (repo / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
assert "registerComponents(root.screen, root)" in panels_patch
assert "unregisterComponents(root.screen, root)" in panels_patch
shell_state = (repo / "cortetsu/modules/CortetsuShellState.qml").read_text(encoding="utf-8")
shell_service = (repo / "cortetsu/services/ShellState.qml").read_text(encoding="utf-8")
screen_component = (repo / "cortetsu/components/ScreenState.qml").read_text(encoding="utf-8")
screens_service = (repo / "cortetsu/services/Screens.qml").read_text(encoding="utf-8")
background = (repo / "cortetsu/modules/background/Background.qml").read_text(encoding="utf-8")
content_window_patch = (repo / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
interactions = (repo / "cortetsu/modules/drawers/Interactions.qml").read_text(encoding="utf-8")
retained_host = (repo / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
scrim_patch = content_window_patch
shortcuts = (repo / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")
calendar = (repo / "cortetsu/modules/CalendarController.qml").read_text(encoding="utf-8")
clipboard = (repo / "cortetsu/modules/ClipboardController.qml").read_text(encoding="utf-8")
controllers = {
    "hardware": (repo / "cortetsu/modules/HardwareController.qml").read_text(encoding="utf-8"),
    "displayManager": (repo / "cortetsu/modules/DisplayController.qml").read_text(encoding="utf-8"),
    "wallpaperManager": (repo / "cortetsu/modules/WallpaperController.qml").read_text(encoding="utf-8"),
    "overview": (repo / "cortetsu/modules/OverviewController.qml").read_text(encoding="utf-8"),
}
hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")

for flag in ("overview", "calendar", "clipboard", "hardware", "displayManager", "wallpaperManager", "keyboards"):
    assert f"property bool {flag}" in state, flag
    assert flag in surface_registry.group("retained"), flag
assert "Surfaces.isRetained(flag)" in policy
# The derived input flags have one definition, in the typed state. The copy
# ScreenState kept had no reader and disagreed about settings.
for derived in ("retainedOverlayOpen", "requiresOverlayLayer", "requiresFullInputMask", "requiresWindowKeyboardFocus"):
    assert f"readonly property bool {derived}:" in state, derived
    assert derived not in screen_component, derived
assert "required property QtObject legacyState" in state
assert "function closeRetainedOverlays" in state
assert "function closeRetainedOverlaysExcept(exceptFlag: string): void" in state
assert "function setRetained(flag: string, value: bool): bool" in state
assert "function resetTransientState(): void" in screen_component
assert "root.resetTransientState();" in screen_component
assert "for (const flag of Surfaces.names)" in screen_component
# One multi-screen transition API for every caller (stabilization O-1/O-2).
for signature in ("function open(states, target, flag)", "function close(states, flag)",
                  "function toggle(states, target, flag)", "function toggleOn(states, target, flag)",
                  "function toggleGuarded(states, target, flag, fullscreen)",
                  "function closeExclusiveEverywhere(states)", "function isRetainedFlag(flag)"):
    assert signature in policy, signature
assert "function openExclusive" not in policy and "function closeOtherRetained" not in policy
assert "function allStates(): var" in shell_state
assert "Geometry" in policy and "popouts" in policy and "wallpaper side effects" in policy
assert 'import "../modules"' in screen_component
assert "import QtQml" in screen_component
assert "cortetsuState" in screen_component
assert "CortetsuShellState.registerState(modelData, root)" in screen_component
assert "CortetsuScreens.screens" in screens_service
assert "import Caelestia" not in screens_service
assert "GlobalConfig" not in screens_service
assert "model: CortetsuScreens.screens" in background
assert "PanelWindow" in background
assert "Caelestia.Config" not in background
assert 'import ".."' in panels_patch
assert "import qs.services" not in shell_state
assert "CortetsuShellState.forScreen(screen)" in shell_service
assert "states[0]?.state" not in shell_state
assert "if (!screen)" in shell_state
assert "if (!monitor)" in shell_state
assert "model: CortetsuScreens.screens" in shell_service
assert "ScreenState {}" in shell_service
assert "component Components: QtObject" in shell_service
assert "states.instances.find(state => state.modelData === screen)" in shell_service
assert "import Caelestia" not in shell_service
assert "import qs.services" not in shell_service
assert "CortetsuOverlayCortetsuOverlayConfig" not in interactions
assert "CortetsuOverlayConfig.border" in interactions
overlay_config = (repo / "cortetsu/modules/CortetsuOverlayConfig.qml").read_text(encoding="utf-8")
for marker in (
    "CortetsuConfig.borderSmoothing",
    "CortetsuConfig.bar.showOnHover",
    "CortetsuConfig.launcher.enabled",
    "CortetsuConfig.dashboard.showOnHover",
    "CortetsuConfig.sidebar.minHoverThreshold",
    "CortetsuConfig.utilities.enabled",
):
    assert marker in overlay_config, marker
assert "CortetsuShellState.registerState(modelData, root)" in screen_component
assert "CortetsuScreenState" in screen_component
assert "import Caelestia" not in screen_component
for marker in ("registerState", "unregisterState", "registerComponents", "unregisterComponents", "CortetsuHypr.focusedMonitor"):
    assert marker in shell_state, marker
assert "function anySidebarOpen" in shell_state
assert "states.instances[0]" not in shell_service
assert "?? CortetsuShellState.forActive()" not in shell_service.split("function forScreen", 1)[1].split("function forActive", 1)[0]

# Every retained overlay window is monitor-owned. Using forActive() in a
# Variants delegate makes all monitor windows mirror the currently focused
# monitor and can create duplicate input owners on multi-monitor sessions.
assert "model: CortetsuScreens.screens" in retained_host
assert "CortetsuShellState.forScreen(modelData)" in retained_host
assert "CortetsuShellState.forActive()" not in retained_host
assert "Qt.alpha(CortetsuDesign.colorSumi, 0.34)" in retained_host
assert "visible: window.surfaceOpen && !window.screenState?.cortetsuState?.overview" in retained_host

shared = (repo / "cortetsu/modules/RetainedSurfaceController.qml").read_text(encoding="utf-8")
assert 'import "CortetsuOverlayPolicy.js" as OverlayPolicy' in shared
assert "OverlayPolicy.open(CortetsuShellState.allStates(), target, root.surfaceKey)" in shared
assert "OverlayPolicy.close(CortetsuShellState.allStates(), root.surfaceKey)" in shared
assert ".legacyState" not in shared
for flag, controller in controllers.items():
    if flag == "overview":
        assert 'OverlayPolicy.open(CortetsuShellState.allStates(), state, "overview")' in controller
        assert 'OverlayPolicy.close(CortetsuShellState.allStates(), "overview")' in controller
    else:
        assert "RetainedSurfaceController {" in controller, flag
        assert f'surfaceKey: "{flag}"' in controller, flag
    assert f"CortetsuShellState.forScreen(screen)?.{flag}" not in controller, flag
    assert ".legacyState" not in controller, flag
    assert "setRetained(" not in controller, f"{flag}: writes go through the policy"
assert 'toggleSurfaceOn(screen, "calendar")' in hub
assert "WallpaperController.open(screen);" in hub
assert 'state.setRetained("wallpaperManager"' not in hub
assert "OverlayPolicy.closeExclusiveEverywhere(CortetsuShellState.allStates());" in hub
assert "readonly property var cortetsuState" in hub
for wrapper, flag in (
    ("calendar/Wrapper.qml", "calendar"),
    ("clipboard/Wrapper.qml", "clipboard"),
    ("hardware/Wrapper.qml", "hardware"),
    ("display/Wrapper.qml", "displayManager"),
    ("overview/Wrapper.qml", "overview"),
    ("wallpaper/Wrapper.qml", "wallpaperManager"),
):
    wrapper_text = (repo / "cortetsu/modules" / wrapper).read_text(encoding="utf-8")
    assert f"screenState?.cortetsuState?.{flag}" in wrapper_text, wrapper
for content_file, flag in (("calendar/Content.qml", "calendar"), ("overview/Content.qml", "overview")):
    content_text = (repo / "cortetsu/modules" / content_file).read_text(encoding="utf-8")
    assert f'cortetsuState?.setRetained("{flag}", false)' in content_text, content_file
for marker in ("closeRetainedOverlays", "requiresWindowKeyboardFocus", "requiresFullInputMask", "retainedOverlayOpen"):
    assert marker in content_window_patch, marker
# SUPER+N closes the Wallpaper Manager through the exclusive group.
assert "wallpaperManager" in surface_registry.group("exclusive")
assert 'root.toggleSurface(CortetsuShellState.forActive(), "sidebar")' in shortcuts
assert "root.screenState?.cortetsuState?.overview ? CortetsuDesign.scrimOpacity" in scrim_patch
for content_file, flag in (
    ("clipboard/Content.qml", "clipboard"),
    ("hardware/Content.qml", "hardware"),
    ("display/Editor.qml", "displayManager"),
    ("wallpaper/Content.qml", "wallpaperManager"),
    ("wallpaper/Wrapper.qml", "wallpaperManager"),
):
    content_text = (repo / "cortetsu/modules" / content_file).read_text(encoding="utf-8")
    assert f'setRetained("{flag}", false)' in content_text, content_file
# F1a O-4: an attached popout opened on one monitor (hover, click or IPC)
# must not close a surface opened on another monitor.
hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
attached = hub[hub.index("function openAttachedControlNow"):hub.index("function showAttachedControlFor")]
assert "closeAllPanels()" not in attached and "closeAllLaunchers()" not in attached, attached
assert "OverlayPolicy.closeExclusiveEverywhere(state ? [state] : [])" in attached, attached

print("PASS: Cortetsu screen state and overlay policy preserve monitor-local ownership and the legacy boundary")
