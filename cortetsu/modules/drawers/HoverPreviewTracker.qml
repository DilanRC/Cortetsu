pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import "../CortetsuOverlayPolicy.js" as SurfacePolicy
import "HoverPreview.js" as HoverPreview

// Shared pointer lifetime for dashboard, launcher, and session previews.
// Each host supplies its own panel geometry and any extra keep-open target.
Item {
    id: root

    required property var hostWindow
    required property ShellScreen screen
    required property var screenState
    required property string surface
    required property Item panel
    property var previewTriggerContains: null
    property var additionalTriggerContains: null
    property int closeDelayMs: 250

    readonly property bool preview: SurfacePolicy.isPreview(screenState, surface)

    function itemRect(item: Item): var {
        if (!item)
            return null;
        const position = item.mapToItem(hostWindow.contentItem, 0, 0);
        return { x: position.x, y: position.y, width: item.width, height: item.height };
    }

    function updatePointer(x: real, y: real): void {
        if (!preview) {
            closeTimer.stop();
            return;
        }

        const inPanel = HoverPreview.contains(itemRect(panel), x, y);
        const trigger = previewTriggerContains ? previewTriggerContains(x, y) : false;
        const additionalTrigger = additionalTriggerContains
            ? additionalTriggerContains(x, y) : false;
        if (HoverPreview.shouldKeepOpen(inPanel, trigger, additionalTrigger)) {
            closeTimer.stop();
            return;
        }
        closeTimer.restart();
    }

    anchors.fill: parent

    HoverHandler {
        enabled: root.preview
        onPointChanged: root.updatePointer(point.position.x, point.position.y)
        onHoveredChanged: {
            if (!hovered) {
                closeTimer.stop();
                Qt.callLater(() => SurfacePolicy.closePreview(root.screenState, root.surface));
            } else {
                root.updatePointer(point.position.x, point.position.y);
            }
        }
    }

    Timer {
        id: closeTimer
        interval: root.closeDelayMs
        repeat: false
        onTriggered: {
            if (root.preview)
                SurfacePolicy.closePreview(root.screenState, root.surface);
        }
    }
}
