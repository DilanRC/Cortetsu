.pragma library

// Resolve only from direct active-window signals. A focused toplevel is not
// treated as the keyboard owner while a layer surface explicitly requests
// exclusive keyboard focus; Quickshell may not expose that layer's active
// state, so that case remains requested_unobserved.
function resolveKeyboardOwner(input) {
    input = input ?? {};
    const focusGrabs = Array.isArray(input.focusGrabs) ? input.focusGrabs : [];
    const hosts = Array.isArray(input.hosts) ? input.hosts : [];
    const candidates = hosts.filter(host => String(host.policy ?? "none") !== "none");
    const candidateNames = candidates.map(host =>
        `${host.monitor}:${host.surface}:${host.policy}`);
    const observed = candidates.filter(host => host.active === true
        && !((host.surface === "drawers" || host.surface === "bottom_hub")
            && focusGrabs.some(grab => grab.monitor === host.monitor))
    ).map(host => ({
        monitor: host.monitor,
        surface: host.surface,
        policy: host.policy,
        source: "QQuickWindow.active"
    }));
    for (const grab of focusGrabs.filter(entry => entry.active === true))
        observed.push({ monitor: grab.monitor, surface: "drawers.focus_grab",
            policy: "focus_grab", source: "HyprlandFocusGrab.active" });

    if (observed.length === 1) {
        const owner = observed[0];
        return { state: "observed", observable: true, surface: owner.surface,
            monitor: owner.monitor, source: owner.source, policy: owner.policy,
            candidates: candidateNames, observed_candidates: [owner] };
    }
    if (observed.length > 1)
        return { state: "ambiguous", observable: false, surface: null,
            monitor: null, source: null, policy: null,
            candidates: candidateNames, observed_candidates: observed };

    const exclusive = candidates.filter(host => host.policy === "exclusive");
    if (exclusive.length === 1) {
        const owner = exclusive[0];
        return { state: "requested_unobserved", observable: false,
            surface: owner.surface, monitor: owner.monitor,
            source: "WlrLayershell.keyboardFocus", policy: owner.policy,
            candidates: candidateNames, observed_candidates: [] };
    }
    if (exclusive.length > 1)
        return { state: "ambiguous_requested", observable: false,
            surface: null, monitor: null, source: "WlrLayershell.keyboardFocus",
            policy: null, candidates: candidateNames, observed_candidates: [] };

    if (input.focusedToplevel)
        return { state: "observed", observable: true, surface: "toplevel",
            monitor: input.focusedToplevel.monitor ?? null,
            source: "Hyprland.focusedToplevel", policy: "toplevel",
            candidates: candidateNames, observed_candidates: [{
                monitor: input.focusedToplevel.monitor ?? null,
                surface: "toplevel", policy: "toplevel", source: "Hyprland.focusedToplevel"
            }] };
    if (candidates.length === 1) {
        const owner = candidates[0];
        return { state: "requested_unobserved", observable: false,
            surface: owner.surface, monitor: owner.monitor,
            source: "WlrLayershell.keyboardFocus", policy: owner.policy,
            candidates: candidateNames, observed_candidates: [] };
    }
    if (candidates.length > 1)
        return { state: "ambiguous_requested", observable: false,
            surface: null, monitor: null, source: "WlrLayershell.keyboardFocus",
            policy: null, candidates: candidateNames, observed_candidates: [] };
    return { state: "unobservable", observable: false, surface: null,
        monitor: null, source: null, policy: null, candidates: [], observed_candidates: [] };
}

function buildSnapshot(input) {
    input = input ?? {};
    const screens = Array.isArray(input.screens) ? input.screens : [];
    const surfaces = [];
    const openStates = [];
    const overlays = [];
    const focusGrabs = [];
    const bottomHub = [];
    const transitions = [];

    for (const screen of screens) {
        const monitor = String(screen.name ?? "");
        for (const surface of (Array.isArray(screen.surfaces) ? screen.surfaces : [])) {
            const entry = {
                monitor,
                surface: String(surface.name ?? ""),
                kind: String(surface.kind ?? "unknown"),
                host: surface.kind === "retained" ? "retained-surfaces"
                    : surface.kind === "chrome" ? "bar" : "drawers",
                open: surface.open === true,
                exclusive: surface.exclusive === true,
                owns_keyboard: surface.ownsKeyboard === true,
                activation_cause: surface.open === true
                    ? String(surface.openCause ?? "explicit") : null
            };
            surfaces.push(entry);
            if (entry.open) {
                openStates.push({ monitor, surface: entry.surface });
                if (entry.kind === "retained")
                    overlays.push({ monitor, surface: entry.surface });
            }
        }

        if (screen.focusGrab) {
            focusGrabs.push({
                monitor,
                requested: screen.focusGrab.requested === true,
                active: screen.focusGrab.active === true,
                observable: screen.focusGrab.observable !== false,
                surface: screen.focusGrab.surface ?? "drawers",
                windows: Array.isArray(screen.focusGrab.windows)
                    ? screen.focusGrab.windows.map(name => String(name)) : [],
                cleared_at_epoch_ms: Number.isFinite(screen.focusGrab.clearedAt)
                    ? screen.focusGrab.clearedAt : 0
            });
        }
        if (screen.bottomHub) {
            bottomHub.push({
                monitor,
                shown: screen.bottomHub.shown === true,
                sidebar: screen.bottomHub.sidebar === true,
                utilities: screen.bottomHub.utilities === true,
                launcher: screen.bottomHub.launcher === true,
                popup: String(screen.bottomHub.popup ?? ""),
                open: screen.bottomHub.open === true,
                closing: screen.bottomHub.closing === true,
                detached: String(screen.bottomHub.detached ?? ""),
                window_active: screen.bottomHub.activeFocus === true,
                keyboard_focus_policy: String(screen.bottomHub.keyboardFocusPolicy ?? "unknown")
            });
        }
        for (const transition of (Array.isArray(screen.transitions) ? screen.transitions : [])) {
            if (transition.active === true) {
                transitions.push({
                    monitor,
                    surface: String(transition.surface ?? "unknown"),
                    progress: Number.isFinite(transition.progress) ? transition.progress : null
                });
            }
        }
    }

    const conflicts = [];
    for (let leftIndex = 0; leftIndex < surfaces.length; ++leftIndex) {
        const left = surfaces[leftIndex];
        if (!left.open || !left.exclusive)
            continue;
        for (let rightIndex = leftIndex + 1; rightIndex < surfaces.length; ++rightIndex) {
            const right = surfaces[rightIndex];
            if (right.open && right.exclusive && right.monitor === left.monitor) {
                conflicts.push({
                    kind: "exclusive_surfaces",
                    surfaces: [left.surface, right.surface],
                    monitors: [left.monitor, right.monitor]
                });
            }
        }
    }

    const focus = input.focus ?? {};
    const fullscreen = input.fullscreen ?? {};
    const queries = input.hyprlandQueries?.clientSnapshots ?? {};
    const eventStream = input.eventStream ?? {};
    const keyboardOwner = focus.keyboardOwner ?? {};

    return {
        schema_version: 2,
        observed_at: input.observedAt ?? null,
        monitors: Array.isArray(input.monitors) ? input.monitors : [],
        surfaces,
        open_states: openStates,
        focus: {
            monitor: focus.monitor ?? null,
            workspace: focus.workspace ?? null,
            window: focus.window ?? null,
            keyboard_owner: {
                state: String(keyboardOwner.state ?? (keyboardOwner.observable === true ? "observed" : "unobservable")),
                observable: keyboardOwner.observable === true,
                surface: keyboardOwner.surface ?? null,
                monitor: keyboardOwner.monitor ?? null,
                source: keyboardOwner.source ?? null,
                policy: keyboardOwner.policy ?? null,
                candidates: Array.isArray(keyboardOwner.candidates) ? keyboardOwner.candidates : [],
                observed_candidates: Array.isArray(keyboardOwner.observed_candidates)
                    ? keyboardOwner.observed_candidates : []
            }
        },
        focus_grabs: focusGrabs,
        bottom_hub: bottomHub,
        overlays,
        fullscreen: {
            focused: fullscreen.focused === true,
            windows: Array.isArray(fullscreen.windows) ? fullscreen.windows : []
        },
        transitions,
        conflicts,
        hyprland_queries: {
            client_snapshots: {
                count: Number.isFinite(queries.count) ? queries.count : 0,
                total_ms: Number.isFinite(queries.totalMs) ? queries.totalMs : 0,
                max_ms: Number.isFinite(queries.maxMs) ? queries.maxMs : 0
            },
            toplevel_refresh_calls: Number.isFinite(input.hyprlandQueries?.toplevelRefreshCalls)
                ? input.hyprlandQueries.toplevelRefreshCalls : 0,
            windowtitle_refresh_calls: Number.isFinite(input.hyprlandQueries?.windowTitleRefreshCalls)
                ? input.hyprlandQueries.windowTitleRefreshCalls : 0
        },
        hyprland_event_stream: {
            quickshell_reconnect_supported: eventStream.quickshellReconnectSupported === true,
            quickshell_status_observable: eventStream.quickshellStatusObservable === true,
            lost: eventStream.lost === true,
            cortetsu_observer_reconnect_supported: eventStream.cortetsuObserverReconnectSupported === true
        }
    };
}

function stringifySnapshot(input) {
    return JSON.stringify(buildSnapshot(input));
}
