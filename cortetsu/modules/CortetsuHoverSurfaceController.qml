pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    visible: false

    property int openDelay: 120
    property int closeDelay: 240
    property bool triggerHovered: false
    property bool popupHovered: false
    property bool pinned: false
    property var pendingScreen: null
    property string pendingMode: ""
    property real pendingAnchor: -1

    signal openRequested(var screen, string mode, real anchorCenter)
    signal closeRequested()

    function request(screen, mode, anchorCenter): void {
        pendingScreen = screen;
        pendingMode = mode;
        pendingAnchor = anchorCenter;
        closeTimer.stop();
        openTimer.restart();
    }

    function enterTrigger(): void {
        triggerHovered = true;
        closeTimer.stop();
    }

    function leaveTrigger(): void {
        triggerHovered = false;
        scheduleClose();
    }

    function enterPopup(): void {
        popupHovered = true;
        closeTimer.stop();
    }

    function leavePopup(): void {
        popupHovered = false;
        scheduleClose();
    }

    function scheduleClose(): void {
        if (!pinned && !triggerHovered && !popupHovered)
            closeTimer.restart();
    }

    function pin(): void {
        pinned = true;
        closeTimer.stop();
    }

    function unpin(): void {
        pinned = false;
        scheduleClose();
    }

    Timer {
        id: openTimer
        interval: root.openDelay
        repeat: false
        onTriggered: {
            if (root.pendingScreen && root.pendingMode.length > 0)
                root.openRequested(root.pendingScreen, root.pendingMode, root.pendingAnchor);
        }
    }

    Timer {
        id: closeTimer
        interval: root.closeDelay
        repeat: false
        onTriggered: if (!root.pinned && !root.triggerHovered && !root.popupHovered)
            root.closeRequested()
    }
}
