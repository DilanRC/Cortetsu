pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../theme"

Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState?.cortetsuState?.keyboards ?? false

    visible: shouldBeActive
    opacity: shouldBeActive ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    // Created on first open, then kept: reopening keeps the selection and
    // costs nothing while closed (the backend stops with `surfaceVisible`).
    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.shouldBeActive || item !== null
        sourceComponent: Content {
            screen: root.screen
            screenState: root.screenState
            surfaceVisible: root.shouldBeActive
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            Qt.callLater(() => contentLoader.item?.openSurface());
    }
}
