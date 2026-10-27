pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../theme"

Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState?.cortetsuState?.keyboards ?? false
    // A capture or a write in progress keeps the surface open against clicks.
    readonly property bool dismissBlocked: contentLoader.item?.pointerDismissBlocked ?? false

    visible: shouldBeActive
    opacity: shouldBeActive ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    // Created on first open, then kept: reopening keeps the selection and
    // costs nothing while closed (the backend stops with `surfaceVisible`).
    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.shouldBeActive || item !== null
        sourceComponent: Content {
            screen: root.screen
            screenState: root.screenState
            surfaceVisible: root.shouldBeActive
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            Qt.callLater(() => contentLoader.item?.openSurface());
    }
}
