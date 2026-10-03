import QtQuick
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root
    required property var screenState
    required property bool sidebarVisible
    readonly property real nonAnimWidth: implicitWidth
    readonly property bool shouldBeActive: screenState?.session === true
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarOffset: sidebarVisible ? CortetsuDesign.spacingStandard : 0

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - CortetsuDesign.spacingStandard - sidebarOffset) * offsetScale
    // The action rows size from this width. Letting both the wrapper and the
    // column infer their width created a polish loop in Quickshell.
    implicitWidth: 440
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic }
    }

    Content {
        id: content
        anchors.left: parent.left
        anchors.top: parent.top
        width: parent.width
        screenState: root.screenState
    }
}
