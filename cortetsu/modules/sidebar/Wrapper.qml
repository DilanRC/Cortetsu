pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    objectName: "cortetsuBottomNotificationCenter"
    required property var screenState
    readonly property bool shouldBeActive: screenState?.sidebar ?? false
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.bottomMargin: 66 + (-implicitHeight - 5 - 66) * offsetScale
    implicitWidth: Math.min(520, parent.width - 16)
    implicitHeight: Math.min(430, parent.height * 0.55)
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Loader {
        id: content
        anchors.fill: parent
        active: root.shouldBeActive || root.visible
        sourceComponent: Content { screenState: root.screenState }
    }
}
