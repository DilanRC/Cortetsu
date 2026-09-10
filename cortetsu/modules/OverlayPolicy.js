.pragma library

// One policy keeps large Cortetsu surfaces mutually exclusive. Retained and
// transient first-party surfaces must not be able to stack into competing
// input owners.
function setFlag(state, flag, value) {
    if (!state)
        return false;
    if (typeof state.setFlag === "function")
        return state.setFlag(flag, value);
    if (state[flag] === undefined)
        return false;
    state[flag] = value;
    return true;
}

function closeOtherPanels(state) {
    if (!state)
        return;
    for (const flag of ["launcher", "session", "dashboard", "utilities", "qsd", "settings", "sidebar",
                        "overview", "calendar", "wallpaperManager", "clipboard", "hardware", "displayManager"])
        setFlag(state, flag, false);
}

function closeForWallpaper(state) {
    if (!state)
        return;
    for (const flag of ["launcher", "session", "dashboard", "utilities", "qsd", "settings", "sidebar",
                        "overview", "calendar", "clipboard", "hardware", "displayManager"])
        setFlag(state, flag, false);
}

function hasCompetingPanel(state) {
    return !!state && (state.launcher || state.session || state.dashboard || state.utilities
        || state.qsd || state.settings || state.sidebar || state.overview || state.calendar
        || state.clipboard || state.hardware || state.displayManager);
}
