import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    focus: !disabled
    activeFocusOnTab: !disabled

    property string title: ""
    property string subtitle: ""
    property var swatches: []
    property bool selected: false
    property bool disabled: false
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    property real visualScale: root.pressed
        ? 0.992
        : root.hovered || root.activeFocus
            ? 1.008
            : 1

    signal clicked()

    implicitWidth: 192
    implicitHeight: 116
    opacity: root.disabled ? 0.46 : 1
    Behavior on visualScale {
        NumberAnimation {
            duration: root.pressed
                ? CortetsuDesign.motionInstantMs
                : CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: root.selected
        disabled: root.disabled
        focused: root.activeFocus
        hovered: root.hovered
        pressed: root.pressed
        scale: root.visualScale
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.74)
        baseColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.74)
            : CortetsuDesign.colorSurfaceGlass
        hoverColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.84)
            : CortetsuDesign.colorSurfaceHigh
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : root.selected
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.58)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)
        outlined: true
    }

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingUnit
        scale: root.visualScale

        CortetsuText {
            width: parent.width
            text: root.title
            textSize: CortetsuTypography.bodyPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            text: root.subtitle
            textSize: CortetsuTypography.labelSmallPx
            color: root.selected
                ? CortetsuDesign.colorPrimary
                : CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }

        Item { width: 1; height: 1 }

        Row {
            spacing: CortetsuDesign.spacingUnit

            Repeater {
                model: root.swatches

                delegate: Rectangle {
                    required property var modelData
                    width: 22
                    height: 22
                    radius: CortetsuDesign.radiusSmall / 2
                    color: modelData
                    border.width: 1
                    border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.16)
                }
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
        onClicked: root.clicked()
    }

    Keys.onEnterPressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
