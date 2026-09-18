import QtQuick
import Quickshell
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../qsd" as FullOsd

// The large OSD is the canonical full system-control surface. The legacy
// QSD host and the compact Utilities card are not instantiated anywhere.
Item {
    id: root

    required property var monitor
    required property var screenState
    required property real volume
    required property bool muted
    required property real brightness
    required property ShellScreen screen
    property bool hovered: false

    implicitWidth: 520
    implicitHeight: content.implicitHeight + CortetsuDesign.spacingSection * 2

    HoverHandler {
        onHoveredChanged: root.hovered = hovered
    }

    CortetsuPopupSurface {
        anchors.fill: parent
        FullOsd.Content {
            id: content
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingSection
            screenState: root.screenState
            screen: root.screen
        }
    }
}
