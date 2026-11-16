pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../services"
import "../../theme"

// Host side of the desktop editor on one monitor. The editor exists only
// while it is open: it draws every widget of the monitor again, and those
// previews hold sampling services.
Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState?.cortetsuState?.desktopWidgets ?? false

    visible: opacity > 0
    opacity: shouldBeActive ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    Loader {
        id: editorLoader
        anchors.fill: parent
        active: root.shouldBeActive
        sourceComponent: Editor {
            screen: root.screen
            screenState: root.screenState
        }
        onLoaded: Qt.callLater(() => editorLoader.item?.openSurface())
    }

    onShouldBeActiveChanged: if (!shouldBeActive) DesktopWidgets.endSession()
}
