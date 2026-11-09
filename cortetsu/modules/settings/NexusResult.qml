pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A search result: the setting found and, below it, where it lives.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string path: ""
    signal activated()

    implicitHeight: Math.max(44, labels.implicitHeight + CortetsuDesign.spacingCompact * 2)
    activeFocusOnTab: true

    Accessible.role: Accessible.Link
    Accessible.name: root.title
    Accessible.description: root.path
    Accessible.onPressAction: root.activated()

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.materialStyle === 2 ? CortetsuDesign.radiusSmall : CortetsuDesign.radiusMedium
        focused: root.activeFocus
        hovered: mouse.containsMouse
        baseColor: "transparent"
        hoverColor: Qt.alpha(CortetsuDesign.colorOnSurface, 0.07)
        outlined: false
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingCompact
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: root.icon
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            spacing: 0

            CortetsuText {
                Layout.fillWidth: true
                text: root.title
                textSize: CortetsuTypography.bodyPx
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.path
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    Keys.onEnterPressed: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
}
