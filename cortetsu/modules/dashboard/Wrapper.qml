import QtQuick
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property var screenState
    readonly property real nonAnimHeight: content.implicitHeight
    readonly property bool shouldBeActive: screenState?.dashboard === true
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - CortetsuDesign.spacingStandard) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        NumberAnimation {
            duration: CortetsuDesign.motionStandardMs
            easing.type: Easing.OutCubic
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
