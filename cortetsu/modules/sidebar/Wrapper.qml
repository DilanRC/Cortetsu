pragma ComponentBehavior: Bound

import QtQuick
import "../../theme"

Item {
    id: root

    objectName: "cortetsuBottomNotificationCenter"
    required property var screenState
    readonly property bool shouldBeActive: screenState?.sidebar ?? false
    property real offsetScale: shouldBeActive ? 0 : 1

    // What the Hub takes from each edge (Panels sets it per screen).
    property var hubReserved: ({ top: 0, bottom: CortetsuDesign.bottomHubHeight, left: 0, right: 0 })

    visible: offsetScale < 1
    // Right-edge drawer: full height, clear of the Hub on whichever edge it
    // sits, sliding in from the edge it is opened from.
    anchors.topMargin: 8 + hubReserved.top
    anchors.bottomMargin: Math.max(8, hubReserved.bottom)
    anchors.rightMargin: (8 + hubReserved.right) * (1 - offsetScale) + (-implicitWidth - 8) * offsetScale
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
