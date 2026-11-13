import QtQuick
import "../../theme"

Item {
    id: root

    required property var screenState
    readonly property real nonAnimHeight: content.implicitHeight
    readonly property bool shouldBeActive: screenState?.dashboard === true
    property real offsetScale: shouldBeActive ? 0 : 1

    // What the Hub takes from each edge (Panels sets it per screen).
    property var hubReserved: ({ top: 0, bottom: CortetsuDesign.bottomHubHeight, left: 0, right: 0 })

    visible: offsetScale < 1
    anchors.topMargin: hubReserved.top * (1 - offsetScale) + (-implicitHeight - CortetsuDesign.spacingStandard) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        NumberAnimation {
            duration: CortetsuDesign.motionStandardMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    Dash {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        screenState: root.screenState
        facePicker: null
    }
}
