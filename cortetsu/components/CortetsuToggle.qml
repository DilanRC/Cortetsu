import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    focus: !disabled
    activeFocusOnTab: !disabled

    property bool checked: false
    property bool disabled: false
    signal toggled(bool checked)

    implicitWidth: 46
    implicitHeight: 26
    opacity: disabled ? 0.46 : 1
    scale: mouse.pressed ? 0.98 : 1

    Behavior on scale {
        NumberAnimation {
            duration: CortetsuDesign.motionInstantMs
            easing.type: Easing.OutCubic
        }
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusPill
        active: root.checked
        disabled: root.disabled
        baseColor: root.checked
            ? Qt.alpha(CortetsuDesign.colorPrimary, 0.78)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
        activeColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.88)
        hoverColor: root.checked
            ? Qt.alpha(CortetsuDesign.colorPrimary, 0.88)
            : CortetsuDesign.colorSurfaceGlassStrong
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.36)
        outlined: true
        focused: root.activeFocus
        hovered: mouse.containsMouse
        pressed: mouse.pressed
    }

    Rectangle {
        id: thumb
        width: 18
        height: width
        radius: width / 2
        x: root.checked ? parent.width - width - 4 : 4
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked
            ? CortetsuDesign.colorWashi
            : CortetsuDesign.colorOnSurfaceMuted
        border.width: 1
        border.color: root.checked
            ? Qt.alpha(CortetsuDesign.colorSumi, 0.22)
            : Qt.alpha(CortetsuDesign.colorOutline, 0.5)

        Behavior on x {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.toggled(!root.checked)
    }

    Keys.onEnterPressed: root.toggled(!root.checked)
    Keys.onReturnPressed: root.toggled(!root.checked)
    Keys.onSpacePressed: root.toggled(!root.checked)
}
