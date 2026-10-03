import QtQuick
import "CortetsuDesign.js" as CortetsuDesign

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
    property color hoverColor: Qt.lighter(baseColor, 1.12)
    property color activeColor: danger
        ? CortetsuDesign.colorVermillion
        : CortetsuDesign.colorIndigo
    property color outlineColor: focused
        ? Qt.alpha(CortetsuDesign.colorWashi, 0.84)
        : danger
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.62)
            : active
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.44)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.34)

    radius: radiusValue
    color: pressed
        ? Qt.darker(active || danger ? activeColor : hoverColor, 1.08)
        : active
            ? activeColor
            : danger
                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.10)
                : hovered
                    ? hoverColor
                    : baseColor
    border.width: outlined || focused ? 1 : 0
    border.color: outlineColor

    Behavior on color {
        ColorAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }
}
