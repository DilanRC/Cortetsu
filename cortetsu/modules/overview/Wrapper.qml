pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../CortetsuDesign.js" as CortetsuDesign

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
            duration: root.shouldBeActive
                ? CortetsuDesign.motionStandardMs
                : CortetsuDesign.motionFastMs
            easing.type: root.shouldBeActive ? Easing.OutCubic : Easing.InCubic
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
