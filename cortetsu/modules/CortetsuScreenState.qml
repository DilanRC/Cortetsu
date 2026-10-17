pragma ComponentBehavior: Bound

import QtQml

// Typed state boundary for controllers and surfaces. ScreenState remains the
// persistence bridge for now, but consumers must use this API instead of
// reaching through to its legacy backing object.
QtObject {
    required property QtObject legacyState

    readonly property bool overview: !!legacyState.overview
    readonly property bool calendar: !!legacyState.calendar
    readonly property bool clipboard: !!legacyState.clipboard
    readonly property bool hardware: !!legacyState.hardware
    readonly property bool displayManager: !!legacyState.displayManager
    readonly property bool wallpaperManager: !!legacyState.wallpaperManager
    readonly property bool keyboards: !!legacyState.keyboards

    readonly property bool retainedOverlayOpen: overview || calendar || clipboard || hardware || displayManager || wallpaperManager || keyboards
    readonly property bool requiresOverlayLayer: retainedOverlayOpen || !!legacyState.launcher || !!legacyState.session
    readonly property bool requiresFullInputMask: overview || calendar || clipboard || hardware || displayManager || wallpaperManager || keyboards
    readonly property bool requiresWindowKeyboardFocus: requiresFullInputMask || !!legacyState.launcher || !!legacyState.session

    function setFlag(flag: string, value: bool): bool {
        if (flag === "overview" || flag === "calendar" || flag === "clipboard"
                || flag === "hardware" || flag === "displayManager" || flag === "wallpaperManager"
                || flag === "keyboards")
            return setRetained(flag, value);
        if (["launcher", "session", "dashboard", "utilities", "settings", "sidebar", "osd"].indexOf(flag) < 0
                || legacyState[flag] === undefined)
            return false;
        legacyState[flag] = value;
        return true;
    }

    function closeRetainedOverlays(): void {
        legacyState.overview = false;
        legacyState.calendar = false;
        legacyState.clipboard = false;
        legacyState.hardware = false;
        legacyState.displayManager = false;
        legacyState.wallpaperManager = false;
        legacyState.keyboards = false;
    }

    function closeRetainedOverlaysExcept(exceptFlag: string): void {
        for (const flag of ["overview", "calendar", "clipboard", "hardware", "displayManager", "wallpaperManager", "keyboards"]) {
            if (flag !== exceptFlag)
                setRetained(flag, false);
        }
    }

    function setRetained(flag: string, value: bool): bool {
        if (flag !== "overview" && flag !== "calendar" && flag !== "clipboard"
                && flag !== "hardware" && flag !== "displayManager" && flag !== "wallpaperManager"
                && flag !== "keyboards")
            return false;
        legacyState[flag] = value;
        return true;
    }
}
