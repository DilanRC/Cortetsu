pragma ComponentBehavior: Bound

import QtQuick
import "../../theme"

Item {
    id: root

    objectName: "cortetsuBottomNotificationCenter"
    required property var screenState
    readonly property bool shouldBeActive: screenState?.sidebar ?? false
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    // Right-edge drawer: full height between the screen top and the
    // BottomHub, sliding in from the edge it is opened from.
    anchors.topMargin: 8
    anchors.bottomMargin: 66
    anchors.rightMargin: 8 + (-implicitWidth - 16) * offsetScale
    implicitWidth: Math.min(420, parent.width - 16)
    opacity: Math.min(1, (1 - offsetScale) * 2)

    Behavior on offsetScale {
        NumberAnimation {
            duration: root.shouldBeActive ? CortetsuDesign.motionStandardMs * 1.4 : CortetsuDesign.motionStandardMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shouldBeActive ? CortetsuDesign.easeDrawer : CortetsuDesign.easeOut
        }
    }

    Loader {
        id: content
        anchors.fill: parent
        active: root.shouldBeActive || root.visible
        sourceComponent: Content { screenState: root.screenState }
    }
}
