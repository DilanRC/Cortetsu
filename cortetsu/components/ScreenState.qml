import QtQml
import Quickshell
import "../modules"

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
    property int dashboardTab
    property date dashboardDate: new Date()

    property bool overview
    property bool calendar
    property bool clipboard
    property bool hardware
    property bool displayManager
    property bool wallpaperManager

    readonly property bool retainedOverlayOpen: overview || calendar || clipboard || hardware || displayManager || wallpaperManager
    readonly property bool requiresOverlayLayer: retainedOverlayOpen || launcher || session || settings
    readonly property bool requiresFullInputMask: retainedOverlayOpen
    readonly property bool requiresWindowKeyboardFocus: requiresFullInputMask || launcher || session || settings

    Component.onCompleted: {
        // Migrate persisted legacy quick-settings flags to the single OSD.
        root.utilities = false;
        CortetsuShellState.registerState(modelData, root);
    }
    Component.onDestruction: CortetsuShellState.unregisterState(modelData, root)
}
