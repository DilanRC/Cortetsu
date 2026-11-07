import QtQml

QtObject {
    id: root

    property bool autoHideEnabled: false
    property bool shown: true
    property bool revealedByHover: false
    property int hoverCount: 0
    property int hideDelayMs: 500
    property Timer autoHideTimer: Timer {
        interval: root.hideDelayMs
        repeat: false
        onTriggered: {
            if (root.autoHideEnabled && root.shown && root.revealedByHover && root.hoverCount === 0) {
                root.shown = false;
                root.revealedByHover = false;
            }
        }
    }

    function setShown(value: bool): void {
        autoHideTimer.stop();
        shown = value;
        revealedByHover = false;
    }

    function cancelAutoHide(): void {
        autoHideTimer.stop();
        revealedByHover = false;
    }

    function pointerEntered(): void {
        if (!autoHideEnabled)
            return;
        hoverCount++;
        autoHideTimer.stop();
        if (!shown) {
            shown = true;
            revealedByHover = true;
        }
    }

    function pointerExited(): void {
        if (!autoHideEnabled)
            return;
        hoverCount = Math.max(0, hoverCount - 1);
        if (shown && revealedByHover && hoverCount === 0)
            autoHideTimer.restart();
    }

    function scheduleInitialHide(): void {
        if (autoHideEnabled && shown && hoverCount === 0) {
            revealedByHover = true;
            autoHideTimer.restart();
        }
    }

    onAutoHideEnabledChanged: {
        if (autoHideEnabled)
            scheduleInitialHide();
        else {
            autoHideTimer.stop();
            revealedByHover = false;
            hoverCount = 0;
            shown = true;
        }
    }

    Component.onCompleted: scheduleInitialHide()

}
