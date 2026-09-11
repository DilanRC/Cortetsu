pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "."
import "../../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness
    readonly property alias content: content
    property real offsetScale: content.hasCurrent && !content.closing ? 0 : 1

    visible: width > 0 && height > 0
    clip: false
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    // Panels places this wrapper as a positioned item, not in a layout. Keep
    // its hit/draw bounds equal to the measured popup so attached popouts are
    // visible and their HoverHandler can receive the pointer.
    width: implicitWidth
    height: implicitHeight

    x: content.isDetached
        ? (parent.width - content.nonAnimWidth) / 2
        : (content.bottomAttached || content.closing)
            ? content.bottomAnchorCenter >= 0
                ? Math.max(8, Math.min(parent.width - content.nonAnimWidth - 8, content.bottomAnchorCenter - content.nonAnimWidth / 2))
                : parent.width - content.nonAnimWidth - content.bottomRightMargin
            : 0
    y: {
        if (content.isDetached)
            return (parent.height - content.nonAnimHeight) / 2;
        if (content.bottomAttached)
            return parent.height - content.nonAnimHeight - content.bottomOffset;
        const off = content.currentCenter - borderThickness - content.nonAnimHeight / 2;
        const diff = parent.height - Math.floor(off + content.nonAnimHeight);
        if (diff < 0)
            return off + diff;
        return Math.max(off, 0);
    }

    Behavior on offsetScale {
        NumberAnimation {
            duration: content.closing ? CortetsuDesign.motionFastMs : CortetsuDesign.motionStandardMs
            easing.type: content.closing ? Easing.InCubic : Easing.OutCubic
        }
    }

    Wrapper {
        id: content
        screen: root.screen
        offsetScale: root.offsetScale
        anchors.verticalCenter: parent.verticalCenter
        // ClipWrapper owns the screen-space placement. Keeping the animated
        // content at the local origin prevents a second horizontal offset
        // from pulling popouts away from their BottomHub/tray icon.
        x: 0
        transformOrigin: Item.Bottom
        opacity: 1 - root.offsetScale
        scale: 1 - 0.025 * root.offsetScale
        transform: Translate { y: 12 * root.offsetScale }
    }
}
