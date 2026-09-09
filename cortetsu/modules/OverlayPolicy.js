.pragma library

// One policy keeps large Cortetsu surfaces mutually exclusive. Retained and
// transient first-party surfaces must not be able to stack into competing
// input owners.
function closeOtherPanels(state) {
    if (!state)
        return;
    state.launcher = false;
    state.session = false;
    state.dashboard = false;
    state.utilities = false;
    if (state.qsd !== undefined)
        state.qsd = false;
    if (state.settings !== undefined)
        state.settings = false;
    state.sidebar = false;
    state.overview = false;
    if (state.calendar !== undefined)
        state.calendar = false;
    state.wallpaperManager = false;
    if (state.clipboard !== undefined)
        state.clipboard = false;
    if (state.hardware !== undefined)
        state.hardware = false;
    if (state.displayManager !== undefined)
        state.displayManager = false;
}

function closeForWallpaper(state) {
    if (!state)
        return;
    state.launcher = false;
    state.session = false;
    state.dashboard = false;
    state.utilities = false;
    if (state.qsd !== undefined)
        state.qsd = false;
    if (state.settings !== undefined)
        state.settings = false;
    state.sidebar = false;
    state.overview = false;
    if (state.calendar !== undefined)
        state.calendar = false;
    if (state.clipboard !== undefined)
        state.clipboard = false;
    if (state.hardware !== undefined)
        state.hardware = false;
    if (state.displayManager !== undefined)
        state.displayManager = false;
}

function hasCompetingPanel(state) {
    return !!state && (state.launcher || state.session || state.dashboard || state.utilities
        || state.qsd || state.settings || state.sidebar || state.overview || state.calendar
        || state.clipboard || state.hardware || state.displayManager);
}
