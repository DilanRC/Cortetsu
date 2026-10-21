.pragma library

// Canonical inventory of the per-screen surface flags. Every flag list in the
// shell is derived from this table. ScreenState and CortetsuScreenState still
// declare one QML property per flag (QML cannot generate properties), and
// test-cortetsu-surface-registry.py fails if either drifts from this table.
//
// kind:
//   retained   first-party overlay hosted by RetainedSurfacesHost: full input
//              mask, OnDemand keyboard, scrim, closed as a group by Escape,
//              focus-grab clear and fullscreen.
//   transient  upstream drawer or panel owned by ContentWindow and its hosts.
//   chrome     bar reveal state; reset with the session, never opened or
//              closed by the overlay policy and not writable through setFlag.
// exclusive     opening any first-party surface closes it (OverlayPolicy).
// ownsKeyboard  while open, the screen's drawer window requests keyboard focus
//               and the overlay layer (CortetsuScreenState derived flags).
// fullscreenGuard  shortcuts and `drawers toggle` do not open it while the
//                  focused workspace is fullscreen (closing still works).
//
// Opening, closing and toggling go through CortetsuOverlayPolicy.open, close
// and toggle for every caller.
//
// The order is the closing order used by OverlayPolicy.closeOtherPanels.
const surfaces = Object.freeze([
    { name: "launcher", kind: "transient", exclusive: true, ownsKeyboard: true, fullscreenGuard: true },
    { name: "session", kind: "transient", exclusive: true, ownsKeyboard: true, fullscreenGuard: true },
    { name: "dashboard", kind: "transient", exclusive: true, ownsKeyboard: false, fullscreenGuard: true },
    { name: "utilities", kind: "transient", exclusive: true, ownsKeyboard: false, fullscreenGuard: true },
    { name: "settings", kind: "transient", exclusive: true, ownsKeyboard: false, fullscreenGuard: true },
    { name: "sidebar", kind: "transient", exclusive: true, ownsKeyboard: false, fullscreenGuard: true },
    { name: "overview", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    { name: "calendar", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    { name: "wallpaperManager", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    { name: "clipboard", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    { name: "hardware", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    { name: "displayManager", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    { name: "keyboards", kind: "retained", exclusive: true, ownsKeyboard: true, fullscreenGuard: false },
    // OSD is a quick-actions drawer that coexists with every other surface.
    { name: "osd", kind: "transient", exclusive: false, ownsKeyboard: false, fullscreenGuard: true },
    { name: "bar", kind: "chrome", exclusive: false, ownsKeyboard: false, fullscreenGuard: false }
].map(entry => Object.freeze(entry)));

function namesWhere(predicate) {
    return Object.freeze(surfaces.filter(predicate).map(entry => entry.name));
}

const names = namesWhere(() => true);
const retained = namesWhere(entry => entry.kind === "retained");
const transient = namesWhere(entry => entry.kind === "transient");
const exclusive = namesWhere(entry => entry.exclusive);
// Wallpaper Manager closes, and is closed by, every other exclusive surface.
const competingWithWallpaper = namesWhere(entry => entry.exclusive && entry.name !== "wallpaperManager");
const keyboardOwners = namesWhere(entry => entry.ownsKeyboard);
const fullscreenGuarded = namesWhere(entry => entry.fullscreenGuard);

function find(name) {
    return surfaces.find(entry => entry.name === name) ?? null;
}

function isKnown(name) {
    return find(name) !== null;
}

function isRetained(name) {
    return find(name)?.kind === "retained";
}

// Flags a caller may write through CortetsuScreenState.setFlag.
function isSettable(name) {
    const kind = find(name)?.kind;
    return kind === "retained" || kind === "transient";
}

function isFullscreenGuarded(name) {
    return find(name)?.fullscreenGuard === true;
}

function anyOpen(state, flags) {
    return !!state && flags.some(flag => !!state[flag]);
}
