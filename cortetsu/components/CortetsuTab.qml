pragma ComponentBehavior: Bound

import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    property string label: ""
    property string icon: ""
    property bool selected: false
    property bool disabled: false
    required property int index
    required property int count
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    signal activated()
    signal previousRequested()
    signal nextRequested()

    focus: root.selected && !root.disabled
    activeFocusOnTab: !root.disabled
    implicitHeight: 40
    opacity: root.disabled ? 0.46 : 1

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: root.selected
        disabled: root.disabled
        focused: root.activeFocus
        hovered: root.hovered
        pressed: root.pressed
        baseColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.76)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.01)
        hoverColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.88)
            : CortetsuDesign.colorSurfaceGlass
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.94)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : root.selected
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.38)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.18)
        outlined: root.activeFocus || root.selected
    }

    Row {
        anchors.centerIn: parent
        spacing: 5

        CortetsuIcon {
            visible: root.icon.length > 0
            text: root.icon
            color: root.selected
                ? CortetsuDesign.colorOnPrimaryContainer
                : CortetsuDesign.colorOnSurfaceVariant
            iconSize: CortetsuTypography.iconSmallPx
        }

        CortetsuText {
            text: root.label
            color: root.selected
                ? CortetsuDesign.colorOnPrimaryContainer
                : CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            font.weight: root.selected ? Font.DemiBold : Font.Normal
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.activated()
    }

    Keys.onEnterPressed: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
    Keys.onLeftPressed: if (root.index > 0) root.previousRequested()
    Keys.onRightPressed: if (root.index < root.count - 1) root.nextRequested()
}
