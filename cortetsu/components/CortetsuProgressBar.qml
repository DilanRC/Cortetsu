import QtQuick
import "../theme"

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
    // The fraction is what animates, not the pixel width, so resizing the bar
    // moves the fill with it instead of trailing behind or past the track.
    property real shownValue: root.normalizedValue

    Behavior on shownValue {
        NumberAnimation {
            duration: root.motionDuration
            easing.type: Easing.OutCubic
        }
    }

    implicitHeight: root.barHeight
    visible: root.value >= 0 || root.visibleWhenUnavailable

    Rectangle {
        anchors.fill: parent
        radius: root.barRadius
        color: root.trackColor
    }

    Rectangle {
        objectName: "fill"
        width: parent.width * root.shownValue
        height: parent.height
        radius: root.barRadius
        color: root.fillColor
    }
}
