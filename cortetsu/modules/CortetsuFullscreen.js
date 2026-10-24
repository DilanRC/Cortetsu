.pragma library

// Whether one of `toplevels` (Hyprland lastIpcObjects) is fullscreen: state 2
// or 3; 1 is maximized. Callers pass the focused workspace's windows, so a
// game fullscreen on another monitor is not interrupted.
function hasFullscreen(toplevels) {
    return (toplevels ?? []).some(toplevel => (toplevel?.fullscreen ?? 0) > 1);
}
