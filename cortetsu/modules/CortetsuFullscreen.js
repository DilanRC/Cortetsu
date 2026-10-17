.pragma library

// Whether the focused monitor shows a fullscreen window (Hyprland state 2 or
// 3; 1 is maximized). Only the focused monitor counts: it owns the keyboard,
// so a game fullscreen on another monitor is not interrupted. `monitors` is a
// list of { focused, activeWorkspace: { toplevels: [lastIpcObject] } }.
function focusedHasFullscreen(monitors) {
    const focused = (monitors ?? []).find(monitor => monitor?.focused);
    return (focused?.activeWorkspace?.toplevels ?? []).some(toplevel => (toplevel?.fullscreen ?? 0) > 1);
}
