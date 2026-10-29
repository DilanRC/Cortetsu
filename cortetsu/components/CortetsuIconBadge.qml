import QtQuick
import "../theme"

// The tinted square that leads a status card. It has no states or outline,
// so it is not a surface and does not nest one.
Rectangle {
    id: root

    property string icon: ""
    // colorIndicator is the primary kept at 3:1 on dark surfaces.
    property color tone: CortetsuDesign.colorIndicator
    property int iconSize: CortetsuDesign.iconMediumPx + 4

    implicitWidth: 40
    implicitHeight: 40
    radius: CortetsuDesign.radiusMedium
    color: Qt.alpha(root.tone, 0.14)

    CortetsuIcon {
        anchors.centerIn: parent
        text: root.icon
        iconSize: root.iconSize
        color: root.tone
    }
}
