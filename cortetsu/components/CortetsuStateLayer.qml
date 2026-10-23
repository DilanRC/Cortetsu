import QtQuick
import "../theme"

MouseArea {
    id: root

    property bool disabled: false
    property bool showHoverBackground: true
    property bool manualPressOverride: false
    property bool manualHoverOverride: false
    property bool shapeMorph: false
    property real hoverOpacity: 0.08
    property real pressedOpacity: 0.08
    // Both the legacy module and first-party component now share one state
    // machine. Disabled overlays must never keep a manual hover/press tint.
    property real stateOpacity: root.disabled || !root.showHoverBackground ? 0
        : root.pressed || root.manualPressOverride ? root.pressedOpacity
        : root.containsMouse || root.manualHoverOverride ? root.hoverOpacity : 0
    readonly property alias rect: base

    property alias color: base.color
    property alias radius: base.radius
    property alias topLeftRadius: base.topLeftRadius
    property alias topRightRadius: base.topRightRadius
    property alias bottomLeftRadius: base.bottomLeftRadius
    property alias bottomRightRadius: base.bottomRightRadius

    anchors.fill: parent
    enabled: !disabled
    hoverEnabled: true
    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

    Rectangle {
        id: base

        anchors.fill: parent
        color: CortetsuDesign.colorOnSurface
        opacity: root.stateOpacity
        radius: root.parent?.radius ?? 0

        Behavior on opacity {
            NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
        }
    }
}
