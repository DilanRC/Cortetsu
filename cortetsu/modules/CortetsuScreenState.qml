pragma ComponentBehavior: Bound

import QtQml
import "SurfaceRegistry.js" as Surfaces

// Typed state boundary for controllers and surfaces. ScreenState remains the
// persistence bridge for now, but consumers must use this API instead of
// reaching through to its legacy backing object. Flag names and groups come
// from SurfaceRegistry.js; one property per retained flag is declared here.
QtObject {
    required property QtObject legacyState

    readonly property bool overview: !!legacyState.overview
    readonly property bool calendar: !!legacyState.calendar
    readonly property bool clipboard: !!legacyState.clipboard
    readonly property bool hardware: !!legacyState.hardware
    readonly property bool displayManager: !!legacyState.displayManager
    readonly property bool wallpaperManager: !!legacyState.wallpaperManager
    readonly property bool keyboards: !!legacyState.keyboards

    readonly property bool retainedOverlayOpen: Surfaces.anyOpen(legacyState, Surfaces.retained)
    readonly property bool requiresOverlayLayer: Surfaces.keyboardOwners.some(flag =>
        !!legacyState[flag] && !isPreview(flag))
    readonly property bool requiresFullInputMask: retainedOverlayOpen
    readonly property bool requiresWindowKeyboardFocus: requiresOverlayLayer

    // This screen's Bottom Hub window, set by BottomHub. The retained-surfaces
    // scrim covers the hub and asks it whether a click fell on the bell.
    property var bottomHub: null
    property var drawerWindow: null
    property var launcherWindow: null
    property var dashboardWindow: null
    property var sessionWindow: null
    property var retainedSurfacesWindow: null
    property bool focusGrabRequested: false
    property bool focusGrabActive: false
    property real fullscreenTransitionProgress: 0
    property var openCauses: ({})

    function openCause(flag: string): string {
        return String(openCauses[flag] ?? "explicit");
    }

    function setOpenCause(flag: string, cause: string): bool {
        if (!Surfaces.isSettable(flag))
            return false;
        const next = Object.assign({}, openCauses);
        if (!cause || cause === "closed")
            delete next[flag];
        else
            next[flag] = cause;
        openCauses = next;
        return true;
    }

    function isPreview(flag: string): bool {
        return ["hover_preview", "drag_preview"].includes(openCause(flag));
    }

    function setFlag(flag: string, value: bool): bool {
        if (Surfaces.isRetained(flag))
            return setRetained(flag, value);
        if (!Surfaces.isSettable(flag) || legacyState[flag] === undefined)
            return false;
        legacyState[flag] = value;
        return true;
    }

    function closeRetainedOverlays(): void {
        for (const flag of Surfaces.retained)
            setRetained(flag, false);
    }

    function closeRetainedOverlaysExcept(exceptFlag: string): void {
        for (const flag of Surfaces.retained) {
            if (flag !== exceptFlag)
                setRetained(flag, false);
        }
    }

    function setRetained(flag: string, value: bool): bool {
        if (!Surfaces.isRetained(flag))
            return false;
        legacyState[flag] = value;
        return true;
    }

    // Compatibility callers still write previewable legacy flags directly.
    // Clear their cause on close so a later direct reopen is explicit.
    property var legacyCauseObserver: Connections {
        target: legacyState
        function onLauncherChanged(): void {
            if (!legacyState.launcher)
                setOpenCause("launcher", "closed");
        }
        function onSessionChanged(): void {
            if (!legacyState.session)
                setOpenCause("session", "closed");
        }
        function onDashboardChanged(): void {
            if (!legacyState.dashboard)
                setOpenCause("dashboard", "closed");
        }
    }
}
