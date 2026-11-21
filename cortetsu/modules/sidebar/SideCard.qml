pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A card of the notification center's side column: a state with its switch
// (do not disturb, private mode) or a link that goes somewhere (Ajustes).
Item {
    id: card
    property string icon
    property string title
    property string detail
    property bool checked: false
    property bool link: false
    signal toggled(bool checked)
    signal activated()

    implicitHeight: cardRow.implicitHeight + CortetsuDesign.spacingStandard * 2

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        hovered: cardMouse.containsMouse
        baseColor: card.checked ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.5)
        outlineColor: card.checked ? Qt.alpha(CortetsuDesign.colorPrimary, 0.34)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        visible: card.link
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.activated()
    }

    RowLayout {
        id: cardRow
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: card.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: card.checked ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            // Wrapped text in a layout needs a width to wrap to, not its
            // one-line width, or the layout never settles.
            Layout.preferredWidth: 1
            spacing: 0
            CortetsuText {
                Layout.fillWidth: true
                text: card.title
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            CortetsuText {
                Layout.fillWidth: true
                text: card.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        CortetsuToggle {
            visible: !card.link
            accessibleName: card.title
            checked: card.checked
            onToggled: checked => card.toggled(checked)
        }

        CortetsuButton {
            visible: card.link
            compact: true
            icon: "chevron_right"
            label: ""
            tooltipText: card.title
            onClicked: card.activated()
        }
    }
}
