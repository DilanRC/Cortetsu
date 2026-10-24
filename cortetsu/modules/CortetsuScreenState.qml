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
    readonly property bool requiresOverlayLayer: Surfaces.anyOpen(legacyState, Surfaces.keyboardOwners)
    readonly property bool requiresFullInputMask: retainedOverlayOpen
    readonly property bool requiresWindowKeyboardFocus: requiresOverlayLayer

    // This screen's Bottom Hub window, set by BottomHub. The retained-surfaces
    // scrim covers the hub and asks it whether a click fell on the bell.
    property var bottomHub: null
    property bool focusGrabRequested: false
    property bool focusGrabActive: false
    property real fullscreenTransitionProgress: 0

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
}
