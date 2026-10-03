pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root
    required property var screenState
    readonly property bool shouldBeActive: screenState?.cortetsuState?.calendar ?? false
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    implicitWidth: Math.min(900, parent.width - CortetsuDesign.spacingComfortable * 2)
    implicitHeight: Math.min(660, parent.height - CortetsuDesign.spacingComfortable * 2)
    y: parent.height - implicitHeight - CortetsuDesign.spacingComfortable + offsetScale * (implicitHeight + 24)
    opacity: 1 - offsetScale
    onShouldBeActiveChanged: if (shouldBeActive) content.forceActiveFocus()

    Behavior on offsetScale { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic } }

    Content {
        id: content
        anchors.fill: parent
        screenState: root.screenState
    }
}
