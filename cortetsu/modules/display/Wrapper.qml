pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState.cortetsuState?.displayManager ?? false

    visible: shouldBeActive
    opacity: shouldBeActive ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.shouldBeActive
        color: Qt.alpha(CortetsuDesign.colorScrim, 0.38)
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: true
        sourceComponent: Content {
            screen: root.screen
            screenState: root.screenState
            displayVisible: root.shouldBeActive
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            Qt.callLater(() => {
                if (contentLoader.item)
                    contentLoader.item.openDisplayManager();
            });
        }
    }
}
