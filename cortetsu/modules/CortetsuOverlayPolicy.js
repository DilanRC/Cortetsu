.pragma library
.import "SurfaceRegistry.js" as Surfaces
.import "OverlayPolicy.js" as Exclusion

// Public policy contract. It deliberately changes state only. Geometry,
// popouts, tray ownership and wallpaper side effects stay in their callers.
//
// `states` is every screen's state (CortetsuShellState.states mapped to
// .state); a state may be the legacy ScreenState, its typed cortetsuState or
// a plain object in tests. Every path that opens, closes or toggles a surface
// (shortcut, IPC, Bottom Hub, Settings, controllers) goes through open, close
// and toggle, so the same operation has the same result whatever asked for it.
function isRetainedFlag(flag) {
    return Surfaces.isRetained(flag);
}

function legacyOf(state) {
    return state?.legacyState ?? state;
}

function sameState(left, right) {
    const canonical = state => state?.cortetsuState?.legacyState
        ?? state?.cortetsuState ?? state?.legacyState ?? state;
    return canonical(left) === canonical(right);
}

function isOpen(state, flag) {
    return !!legacyOf(state)?.[flag];
}

function openAnywhere(states, flag) {
    return (states ?? []).some(state => isOpen(state, flag));
}

// Exclusive surfaces are exclusive across screens: a retained surface owns the
// keyboard of the whole seat, and a transient panel arms a focus grab that a
// surface on another screen would clear. OSD and the bar are not exclusive and
// stay as they are.
function closeExclusiveEverywhere(states, exceptTarget = null, exceptFlag = "") {
    for (const state of states ?? []) {
        if (!sameState(state, exceptTarget)) {
            Exclusion.closeOtherPanels(state);
            continue;
        }
        for (const flag of Surfaces.exclusive)
            if (flag !== exceptFlag)
                Exclusion.setFlag(state, flag, false);
    }
}

// Opens `flag` on `target`. Opening an exclusive surface first closes every
// exclusive surface on every screen, `flag` included, so a retained surface
// moves to `target` instead of being open twice.
function open(states, target, flag) {
    if (!target || !Surfaces.isSettable(flag))
        return false;
    target.cortetsuState?.setOpenCause(flag, "explicit");
    if (Surfaces.find(flag).exclusive)
        closeExclusiveEverywhere(states, target, flag);
    return Exclusion.setFlag(target, flag, true);
}

// A hover or drag preview can coexist with an explicit surface on another
// monitor (F1a O-4), but cannot compete with one on its own monitor. Preview
// causes never request keyboard focus.
function openPreview(states, target, flag, cause) {
    if (!target || !Surfaces.isPreviewable(flag) || !["hover", "drag"].includes(cause))
        return false;
    const typed = target.cortetsuState;
    if ((states ?? []).length > 0 && !states.includes(target))
        return false;
    const hasLocalExclusive = Surfaces.exclusive.some(name => name !== flag
        && isOpen(target, name));
    if (hasLocalExclusive || (isOpen(target, flag) && !typed?.isPreview(flag)))
        return false;
    const openCause = `${cause}_preview`;
    if (isOpen(target, flag) && typed?.openCause(flag) === openCause)
        return true;
    typed?.setOpenCause(flag, openCause);
    return Exclusion.setFlag(target, flag, true);
}

function isPreview(target, flag) {
    return target?.cortetsuState?.isPreview(flag) === true;
}

// Keep an explicit layer from reverting to Exclusive before a preview on a
// different monitor receives the pointer-leave event that closes it.
function hasPreviewOnOtherScreen(states, target) {
    return (states ?? []).some(state => !sameState(state, target)
        && Surfaces.previewable.some(flag => isPreview(state, flag)));
}

// Promoting a preview uses the ordinary explicit policy, so the seat keeps a
// single keyboard owner after the user chooses to interact with it.
function promotePreview(states, target, flag) {
    if (!isPreview(target, flag))
        return false;
    return open(states, target, flag);
}

function closeOn(target, flag) {
    if (!target || !Surfaces.isSettable(flag))
        return false;
    target.cortetsuState?.setOpenCause(flag, "closed");
    return Exclusion.setFlag(target, flag, false);
}

function closePreview(target, flag) {
    if (!isPreview(target, flag))
        return false;
    return closeOn(target, flag);
}

function close(states, flag) {
    if (!Surfaces.isSettable(flag))
        return false;
    for (const state of states ?? [])
        closeOn(state, flag);
    return true;
}

// Toggle as seen from one screen (Bottom Hub buttons): open on `target`,
// moving it from another screen, unless it is already open there. Returns
// whether `flag` ends open on `target`.
function toggleOn(states, target, flag) {
    if (!target || !Surfaces.isSettable(flag))
        return false;
    if (isOpen(target, flag)) {
        if (isPreview(target, flag))
            return promotePreview(states, target, flag);
        closeOn(target, flag);
        return false;
    }
    return open(states, target, flag);
}

// Toggle for shortcuts and IPC. A retained surface is one instance for the
// seat, so toggling it from any screen closes it wherever it is; a transient
// surface toggles on `target`.
function toggle(states, target, flag) {
    if (isRetainedFlag(flag) && openAnywhere(states, flag)) {
        close(states, flag);
        return false;
    }
    return toggleOn(states, target, flag);
}

// toggle(), except that a fullscreen window on the focused workspace blocks
// opening a guarded surface. Closing is never blocked.
function toggleGuarded(states, target, flag, fullscreen) {
    if (fullscreen && Surfaces.isFullscreenGuarded(flag) && !isOpen(target, flag))
        return false;
    return toggle(states, target, flag);
}
