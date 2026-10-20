.pragma library
.import "SurfaceRegistry.js" as Surfaces
.import "OverlayPolicy.js" as Exclusion

// Public policy contract. It deliberately changes state only. Geometry,
// popouts, tray ownership and wallpaper side effects stay in their callers.
const retainedFlags = Surfaces.retained;

function isRetainedFlag(flag) {
    return Surfaces.isRetained(flag);
}

function closeRetained(state) {
    Exclusion.closeFlags(state, retainedFlags);
}

function closeOtherRetained(state, exceptFlag) {
    if (!state || !isRetainedFlag(exceptFlag))
        return false;
    Exclusion.closeFlags(state, retainedFlags.filter(flag => flag !== exceptFlag));
    return true;
}

// Same group as OverlayPolicy.closeOtherPanels: every exclusive surface.
function closeAll(state) {
    Exclusion.closeOtherPanels(state);
}

function openExclusive(state, flag) {
    if (!state || !isRetainedFlag(flag))
        return false;
    closeAll(state);
    return Exclusion.setFlag(state, flag, true);
}

function retainedOverlayOpen(state) {
    return Surfaces.anyOpen(state?.legacyState ?? state, retainedFlags);
}
