pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive:
        screenState?.cortetsuState?.clipboard ?? false

    visible: shouldBeActive
    opacity: shouldBeActive ? 1 : 0
    scale: shouldBeActive ? 1 : 0.985
    transformOrigin: Item.Center

    Behavior on opacity {
        NumberAnimation {
            duration: 110
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 110
        }
    }

    /*
     * Only the desktop scrim is translucent. Content.qml owns a fully opaque
     * adaptive dark panel, so bright wallpapers cannot bleed through it.
     */
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(CortetsuDesign.colorScrim, 0.17)
        visible: root.shouldBeActive
    }

    Loader {
        id: contentLoader

        anchors.fill: parent

        /*
         * No hidden clipboard tree: closing the drawer destroys FileView,
         * ListView and image preview delegates. The Clipse listener remains
         * the lightweight history backend for the whole session.
         */
        active: root.shouldBeActive

        sourceComponent: Content {
            screen: root.screen
            screenState: root.screenState
            clipboardVisible: root.shouldBeActive
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            Qt.callLater(() => {
                if (contentLoader.item)
                    contentLoader.item.openClipboard();
            });
        }
    }
}
