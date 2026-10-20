.pragma library
.import "SurfaceRegistry.js" as Surfaces

// One policy keeps large Cortetsu surfaces mutually exclusive. Retained and
// transient first-party surfaces must not be able to stack into competing
// input owners. The flag sets come from SurfaceRegistry.js.

// Writes go through CortetsuScreenState.setFlag, so the retained invariants
// (setRetained) apply whether the caller holds the typed state or the legacy
// ScreenState. Plain objects (QML unit tests) are written directly.
function setFlag(state, flag, value) {
    if (!state || !Surfaces.isKnown(flag))
        return false;
    const typed = typeof state.setFlag === "function" ? state : state.cortetsuState;
    if (typed && typeof typed.setFlag === "function")
        return typed.setFlag(flag, value);
    if (state[flag] === undefined)
        return false;
    state[flag] = value;
    return true;
}

function closeFlags(state, flags) {
    if (!state)
        return;
    for (const flag of flags)
        setFlag(state, flag, false);
}

function closeOtherPanels(state) {
    closeFlags(state, Surfaces.exclusive);
}

function closeForWallpaper(state) {
    closeFlags(state, Surfaces.competingWithWallpaper);
}

// Reads the legacy object when given the typed state: CortetsuScreenState
// exposes only the retained flags.
function hasCompetingPanel(state) {
    return Surfaces.anyOpen(state?.legacyState ?? state, Surfaces.competingWithWallpaper);
}
