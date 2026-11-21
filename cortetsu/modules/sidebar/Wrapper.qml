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
    // The room between the Hub and the opposite edge; the center is as tall
    // as its content up to this, and scrolls past it.
    property real availableHeight: 800
    // Sits on the Hub's edge when the Hub takes the top or the bottom, so it
    // opens out of the Hub rather than at the far end of the screen.
    readonly property bool fromBottom: hubReserved.bottom > 0

    visible: offsetScale < 1
    // Right-edge drawer, clear of the Hub on whichever edge it sits, sliding
    // in from that edge.
    anchors.rightMargin: (8 + hubReserved.right) * (1 - offsetScale) + (-implicitWidth - 8) * offsetScale
    implicitWidth: content.item?.implicitWidth ?? 420
    implicitHeight: content.item?.implicitHeight ?? 0
    opacity: Math.min(1, (1 - offsetScale) * 2)

    Behavior on offsetScale {
        NumberAnimation {
            duration: root.shouldBeActive ? CortetsuDesign.motionStandardMs * 1.4 : CortetsuDesign.motionStandardMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shouldBeActive ? CortetsuDesign.easeDrawer : CortetsuDesign.easeOut
        }
    }

    // The ink ground is drawn behind it at this geometry (ContentWindow's
    // PanelBg), so the center's size is the material's size.
    Loader {
        id: content
        anchors.fill: parent
        active: root.shouldBeActive || root.visible
        sourceComponent: Content {
            screenState: root.screenState
            maxHeight: root.availableHeight
            // Wide view on a screen with room for the side column next to
            // the list and the Hub's own reach.
            wide: (root.parent?.width ?? 0) >= 1600
        }
    }
}
