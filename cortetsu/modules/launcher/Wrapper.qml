pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../CortetsuDesign.js" as CortetsuDesign
import ".."
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property var panels

    readonly property bool shouldBeActive: screenState.launcher
    readonly property real dockOffset: 72
    readonly property real maxHeight: {
        let max = (screen?.height ?? 0) + CortetsuDesign.spacingSpacious - dockOffset;
        if (screenState.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive ? 0 : 1

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            implicitHeight = Qt.binding(() => content.implicitHeight);
        else
            implicitHeight = implicitHeight;
    }

    visible: offsetScale < 1
    anchors.bottomMargin:
        dockOffset +
        (-implicitHeight - 5 - dockOffset) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630
    opacity: 1 - offsetScale

    Component.onCompleted: Qt.callLater(() => Apps)

    Behavior on offsetScale {
        NumberAnimation {
            duration: root.shouldBeActive
                ? CortetsuDesign.motionStandardMs
                : CortetsuDesign.motionFastMs
            easing.type: root.shouldBeActive ? Easing.OutCubic : Easing.InCubic
        }
    }

    Loader {
        id: content
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        active: true
        sourceComponent: Content {
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight
        }
    }
}
