import QtQuick
import "CortetsuDesign.js" as CortetsuDesign

MouseArea {
    id: root

    property bool disabled: false
    property bool showHoverBackground: true
    property bool manualPressOverride: false
    property bool manualHoverOverride: false
    property real stateOpacity: !showHoverBackground || disabled ? 0
        : pressed || manualPressOverride ? 0.16
        : containsMouse || manualHoverOverride ? 0.08 : 0
    property real radius: 0
    property alias color: base.color

    anchors.fill: parent
    enabled: !disabled
    hoverEnabled: true
    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

    Rectangle {
        id: base

        anchors.fill: parent
        color: CortetsuDesign.colorOnSurface
        opacity: root.stateOpacity
        radius: root.radius

        Behavior on opacity {
            NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
        }
    }
}
