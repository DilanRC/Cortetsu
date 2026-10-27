import QtQuick
import "../theme"
import "../modules"

Rectangle {
    id: root

    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool focused: false
    property bool disabled: false
    property bool danger: false
    property bool outlined: true
    property real radiusValue: CortetsuDesign.radiusMedium
    property color baseColor: CortetsuDesign.colorTetsu
    property color hoverColor: Qt.lighter(baseColor, 1.16)
    property color activeColor: danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndigo
    // Indigo marks interaction and vermillion only danger. At rest the edge
    // is a translucent hairline rather than a solid border.
    property color outlineColor: focused ? CortetsuDesign.colorWashi
        : danger ? CortetsuDesign.colorVermillion
        : active ? CortetsuDesign.colorIndicator
        : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.56)

    readonly property real transparencyFactor: CortetsuConfig.transparencyEnabled ? 0.78 : 1

    function paintColor(value): color {
        const colour = Qt.color(value);
        return Qt.rgba(colour.r, colour.g, colour.b, colour.a * root.transparencyFactor);
    }

    radius: radiusValue
    color: root.paintColor(pressed ? Qt.darker(active ? activeColor : hoverColor, 1.12) : active ? activeColor : hovered ? hoverColor : baseColor)
    // Keyboard focus reads at a glance: a 2 px washi ring.
    border.width: focused ? CortetsuDesign.outlineWidth * 2 : outlined ? CortetsuDesign.outlineWidth : 0
    border.color: outlineColor

    Behavior on color {
        ColorAnimation {
            duration: CortetsuDesign.motionStandardMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }
}
