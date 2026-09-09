import QtQuick
import QtQuick.Layouts
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    focus: root.clickable && !root.disabled
    activeFocusOnTab: root.clickable && !root.disabled

    property string label: ""
    property string icon: ""
    property string detail: ""
    property bool highlighted: false
    property bool warning: false
    property bool clickable: true
    property bool disabled: false
    readonly property bool hovered: root.clickable && mouse.containsMouse
    readonly property bool pressed: root.clickable && mouse.pressed
    signal activated()

    implicitHeight: 76
    opacity: root.disabled ? 0.46 : 1

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: false
        disabled: root.disabled
        focused: root.activeFocus
        hovered: root.hovered
        pressed: root.pressed
        baseColor: root.warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.10)
            : root.highlighted
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.64)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
        hoverColor: root.warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.16)
            : root.highlighted
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.82)
                : Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.92)
        activeColor: root.warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.22)
            : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.92)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : root.warning
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.44)
                : root.highlighted
                    ? Qt.alpha(CortetsuDesign.colorPrimary, 0.38)
                    : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)
        outlined: true
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: root.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: root.warning
                ? CortetsuDesign.colorWarning
                : root.highlighted
                    ? CortetsuDesign.colorPrimary
                    : CortetsuDesign.colorOnSurface
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            CortetsuText {
                Layout.fillWidth: true
                text: root.label
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                text: root.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.clickable && !root.disabled
        hoverEnabled: enabled
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.activated()
    }

    Keys.onEnterPressed: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
}
