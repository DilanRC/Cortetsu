pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../theme"

Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState?.cortetsuState?.overview ?? false
    property real visibilityProgress: shouldBeActive ? 1 : 0

    visible: visibilityProgress > 0.001
    opacity: visibilityProgress

    Behavior on visibilityProgress {
        NumberAnimation {
            // Opened from a key: only opacity, under 150 ms.
            duration: root.shouldBeActive ? CortetsuDesign.motionSummonMs : CortetsuDesign.motionSummonExitMs
            easing.type: Easing.OutCubic
        }
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: true
        sourceComponent: Content {
            screen: root.screen
            screenState: root.screenState
            overviewVisible: root.shouldBeActive
            tracking: root.shouldBeActive || root.visible
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            Qt.callLater(() => {
                if (contentLoader.item)
                    contentLoader.item.openOverview();
            });
        }
    }
}
