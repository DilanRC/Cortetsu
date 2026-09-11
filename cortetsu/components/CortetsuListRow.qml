import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    focus: !disabled
    activeFocusOnTab: !disabled

    property string icon
    property string title
    property string subtitle
    property bool selected: false
    property bool disabled: false
    signal clicked()

    implicitHeight: CortetsuDesign.rowHeight
    opacity: disabled ? 0.46 : 1
    property real visualScale: mouse.pressed ? 0.992 : 1
    // Keep the row's pointer bounds and layout stable. Only its painted
    // content contracts for press feedback, matching CortetsuButton.
    scale: 1

    Behavior on visualScale {
        NumberAnimation {
            duration: CortetsuDesign.motionInstantMs
            easing.type: Easing.OutCubic
        }
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: root.selected
        disabled: root.disabled
        focused: root.activeFocus
        baseColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.62)
            : "transparent"
        hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.72)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            : root.selected
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.32)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.14)
        outlined: root.selected
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        scale: root.visualScale
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        visible: root.selected
        width: 2
        height: 24
        radius: 1
        color: CortetsuDesign.colorWashi
        opacity: 0.88
        scale: root.visualScale
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard
        scale: root.visualScale

        Item {
            visible: root.icon.length > 0
            width: visible ? 34 : 0
            height: 34
            anchors.verticalCenter: parent.verticalCenter

            CortetsuSurface {
                anchors.fill: parent
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: root.selected
                    ? Qt.alpha(CortetsuDesign.colorPrimary, 0.16)
                    : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.68)
                outlined: false
            }

            CortetsuIcon {
                anchors.centerIn: parent
                text: root.icon
                iconSize: CortetsuDesign.iconMediumPx
                color: root.selected
                    ? CortetsuDesign.colorWashi
                    : CortetsuDesign.colorPrimary
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: Math.max(0, parent.width - x)

            CortetsuText {
                width: parent.width
                text: root.title
                textSize: CortetsuDesign.bodyPx
                color: root.selected
                    ? CortetsuDesign.colorOnPrimaryContainer
                    : CortetsuDesign.colorOnSurface
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            CortetsuText {
                width: parent.width
                visible: text.length > 0
                text: root.subtitle
                textSize: CortetsuDesign.labelSmallPx
                color: root.selected
                    ? Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.72)
                    : CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
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
