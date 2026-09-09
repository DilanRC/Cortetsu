import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    focus: !disabled
    activeFocusOnTab: !disabled

    property string label
    property string icon
    property bool active: false
    property bool danger: false
    property bool disabled: false
    property bool compact: false
    property string tooltipText: ""
    signal clicked()

    implicitWidth: row.implicitWidth + CortetsuDesign.spacingStandard * 2
    implicitHeight: compact ? 32 : CortetsuDesign.controlHeight
    opacity: disabled ? 0.48 : 1
    scale: mouse.pressed ? 0.98 : mouse.containsMouse ? 1.008 : 1

    Behavior on scale {
        NumberAnimation {
            duration: mouse.pressed
                ? CortetsuDesign.motionInstantMs
                : CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    CortetsuSurface {
        id: surface
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusPill
        active: root.active
        danger: root.danger
        disabled: root.disabled
        focused: root.activeFocus
        baseColor: root.danger
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.08)
            : root.active
                ? CortetsuDesign.colorPrimary
                : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.86)
        hoverColor: root.danger
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.14)
            : root.active
                ? Qt.lighter(CortetsuDesign.colorPrimary, 1.08)
                : CortetsuDesign.colorSurfaceGlassStrong
        outlined: !root.active || root.danger
        hovered: mouse.containsMouse
        pressed: mouse.pressed
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: CortetsuDesign.spacingCompact

        CortetsuIcon {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: root.compact
                ? CortetsuTypography.iconSmallPx
                : CortetsuTypography.iconMediumPx
            color: root.danger
                ? CortetsuDesign.colorVermillion
                : root.active
                    ? CortetsuDesign.colorOnPrimary
                    : CortetsuDesign.colorOnSurface
            anchors.verticalCenter: parent.verticalCenter
        }

        CortetsuText {
            visible: root.label.length > 0
            text: root.label
            textSize: root.compact
                ? CortetsuTypography.labelMediumPx
                : CortetsuTypography.bodyPx
            color: root.danger
                ? CortetsuDesign.colorVermillion
                : root.active
                    ? CortetsuDesign.colorOnPrimary
                    : CortetsuDesign.colorOnSurface
            font.weight: root.active ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
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

    CortetsuTooltip {
        target: root
        hovered: mouse.containsMouse
        focused: root.activeFocus
        text: root.tooltipText
    }

    Keys.onEnterPressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
