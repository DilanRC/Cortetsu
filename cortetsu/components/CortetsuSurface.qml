import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign
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
    property color outlineColor: focused ? CortetsuDesign.colorWashi : active || danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOutlineVariant

    readonly property real transparencyFactor: CortetsuConfig.transparencyEnabled ? 0.78 : 1

    function paintColor(value): color {
        const colour = Qt.color(value);
        return Qt.rgba(colour.r, colour.g, colour.b, colour.a * root.transparencyFactor);
    }

    radius: radiusValue
    color: root.paintColor(pressed ? Qt.darker(active ? activeColor : hoverColor, 1.12) : active ? activeColor : hovered ? hoverColor : baseColor)
    border.width: outlined || focused ? CortetsuDesign.outlineWidth : 0
    border.color: outlineColor

    Behavior on color {
        ColorAnimation {
            duration: CortetsuDesign.motionStandardMs
            easing.type: Easing.OutCubic
        }
    }
}
