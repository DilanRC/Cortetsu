import QtQml
import Quickshell
import "../modules"
import "../modules/SurfaceRegistry.js" as Surfaces

PersistentProperties {
    id: root
    required property ShellScreen modelData

    readonly property CortetsuScreenState cortetsuState: CortetsuScreenState {
        legacyState: root
    }

    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool settings
    property bool sidebar
    // When the drawer's focus grab last closed an open sidebar (ms epoch).
    property real sidebarGrabClearedAt
    property int dashboardTab
    property date dashboardDate: new Date()

    property bool overview
    property bool calendar
    property bool clipboard
    property bool hardware
    property bool displayManager
    property bool wallpaperManager
    property bool keyboards

    // Derived input/layer flags live only in cortetsuState.
    function resetTransientState(): void {
        for (const flag of Surfaces.names)
            root[flag] = false;
    }

    Component.onCompleted: {
        // Overlay visibility and input ownership are session state, never preferences.
        root.resetTransientState();
        CortetsuShellState.registerState(modelData, root);
    }
    Component.onDestruction: CortetsuShellState.unregisterState(modelData, root)
}
