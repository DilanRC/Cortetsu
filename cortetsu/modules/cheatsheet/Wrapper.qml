pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../theme"

Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState?.cortetsuState?.cheatsheet ?? false

    visible: opacity > 0
    opacity: shouldBeActive ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    // Created on the first open and kept: the list is read again on every
    // open, so a shortcut edited meanwhile shows up.
    Loader {
        id: contentLoader
        anchors.centerIn: parent
        width: Math.min(1120, parent.width - CortetsuDesign.spacingSection * 2)
        height: Math.min(760, parent.height - CortetsuDesign.spacingSection * 2)
        active: root.shouldBeActive || item !== null
        sourceComponent: Content {
            screenState: root.screenState
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            Qt.callLater(() => contentLoader.item?.openSurface());
    }
}
