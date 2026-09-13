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
    property bool qsd
    property bool qsdEdgeHovered
    property bool qsdDrawerHovered
    property bool qsdOpenedByShortcut
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
    readonly property bool requiresOverlayLayer: retainedOverlayOpen || launcher || session || qsd || settings
    readonly property bool requiresFullInputMask: retainedOverlayOpen
    readonly property bool requiresWindowKeyboardFocus: requiresFullInputMask || launcher || session || qsd || settings

    Component.onCompleted: CortetsuShellState.registerState(modelData, root)
    Component.onDestruction: CortetsuShellState.unregisterState(modelData, root)
}
