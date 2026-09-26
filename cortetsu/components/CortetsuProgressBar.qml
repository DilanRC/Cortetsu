import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    property real value: 0
    property bool visibleWhenUnavailable: false
    property color trackColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.32)
    property color fillColor: CortetsuDesign.colorPrimary
    property real barHeight: 5
    property real barRadius: CortetsuDesign.radiusPill
    property int motionDuration: CortetsuDesign.motionStandardMs

    readonly property real normalizedValue: Math.max(0, Math.min(1, root.value))

    implicitHeight: root.barHeight
    visible: root.value >= 0 || root.visibleWhenUnavailable

    Rectangle {
        anchors.fill: parent
        radius: root.barRadius
        color: root.trackColor
    }

    Rectangle {
        width: parent.width * root.normalizedValue
        height: parent.height
        radius: root.barRadius
        color: root.fillColor

        Behavior on width {
            NumberAnimation {
                duration: root.motionDuration
                easing.type: Easing.OutCubic
            }
        }
    }
}
