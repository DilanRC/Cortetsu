pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    visible: false

    property int openDelay: 120
    property int closeDelay: 240
    property bool triggerHovered: false
    readonly property bool popupHovered: CortetsuShellState.attachedPopupHoverOwner !== null
    property bool pinned: false
    property var pendingScreen: null
    property string pendingMode: ""
    property real pendingAnchor: -1

    signal openRequested(var screen, string mode, real anchorCenter)
    signal closeRequested()

    function hasPendingPopup(): bool {
        if (!pendingScreen)
            return false;
        const popouts = CortetsuShellState.componentsFor(pendingScreen)?.popouts;
        return !!popouts && popouts.hasCurrent && popouts.bottomAttached && !popouts.closing;
    }

    function request(screen, mode, anchorCenter): void {
        const samePending = pendingScreen === screen
            && pendingMode === mode
            && pendingAnchor === anchorCenter;
        pendingScreen = screen;
        pendingMode = mode;
        pendingAnchor = anchorCenter;
        closeTimer.stop();
        // Crossing adjacent controls keeps the original dwell. A real mode
        // change while a popup is open gets a bounded handoff delay.
        if (openTimer.running || (samePending && hasPendingPopup()))
            return;
        openTimer.restart();
    }

    function cancelPending(): void {
        openTimer.stop();
        closeTimer.stop();
        pendingScreen = null;
        pendingMode = "";
        pendingAnchor = -1;
        triggerHovered = false;
    }

    function enterTrigger(): void {
        triggerHovered = true;
        closeTimer.stop();
    }

    function leaveTrigger(): void {
        triggerHovered = false;
        // A dwell that never completed must not flash a popup after the pointer
        // has already left the status icon.
        // Popup ownership only protects an already-open surface. It must never
        // allow a stale trigger dwell to fire after the pointer left the icon.
        openTimer.stop();
        scheduleClose();
    }

    function enterPopup(): void {
        CortetsuShellState.enterAttachedPopup(root);
    }

    function leavePopup(): void {
        CortetsuShellState.leaveAttachedPopup(root);
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

    onPopupHoveredChanged: {
        if (popupHovered)
            closeTimer.stop();
        else
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
