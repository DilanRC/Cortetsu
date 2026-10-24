.pragma library

function emptyPlan() {
    return { refreshMonitors: false, refreshWorkspaces: false, refreshToplevels: false };
}

function refreshPlan(name) {
    const plan = emptyPlan();
    if (typeof name !== "string")
        return plan;

    // Quickshell consumes windowtitlev2 and activewindowv2 itself. Hyprland
    // also emits these legacy aliases when a focused window's title changes;
    // refreshing j/clients for either alias duplicates that model update.
    if (name === "windowtitle" || name === "activewindow" || name.endsWith("v2"))
        return plan;

    if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(name)) {
        plan.refreshMonitors = true;
        plan.refreshWorkspaces = true;
    } else if (["openwindow", "closewindow", "movewindow"].includes(name)) {
        plan.refreshWorkspaces = true;
        plan.refreshToplevels = true;
    } else if (name.includes("mon")) {
        plan.refreshMonitors = true;
    } else if (name.includes("workspace")) {
        plan.refreshWorkspaces = true;
    } else if (name.includes("window") || name.includes("group")
               || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(name)) {
        plan.refreshToplevels = true;
    }
    return plan;
}
