pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: action

    required property string title
    property string detail: ""
    property string icon: "arrow_forward"
    signal activated()

    focus: false
    activeFocusOnTab: true

    Layout.fillWidth: true
    implicitHeight: 64
    radiusValue: CortetsuDesign.radiusMedium
    baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.30)
    hoverColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.52)
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.28)
    focused: action.activeFocus
    hovered: actionMouse.containsMouse
    pressed: actionMouse.pressed

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: action.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: CortetsuDesign.colorPrimary
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            CortetsuText {
                Layout.fillWidth: true
                text: action.title
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            CortetsuText {
                Layout.fillWidth: true
                visible: action.detail.length > 0
                text: action.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
        CortetsuIcon {
            text: "chevron_right"
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }

    MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: action.forceActiveFocus()
        onClicked: action.activated()
    }

    Keys.onEnterPressed: action.activated()
    Keys.onReturnPressed: action.activated()
    Keys.onSpacePressed: action.activated()
}
