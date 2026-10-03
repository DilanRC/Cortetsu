import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// Context that matters less than the meters: one line, no frame at rest.
NavBlock {
    id: root

    property string icon: ""
    property string title: ""
    property string value: ""

    framed: false
    compact: true
    padding: CortetsuDesign.spacingStandard
    radiusValue: CortetsuDesign.radiusMedium
    accessibleName: `${root.title}: ${root.value}`

    CortetsuIcon {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: CortetsuDesign.colorOnSurfaceMuted
        iconSize: CortetsuTypography.iconMediumPx
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.right: parent.right
        anchors.rightMargin: 28
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        CortetsuText {
            width: parent.width
            text: root.title
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            text: root.value
            textSize: CortetsuTypography.bodyPx
            elide: Text.ElideRight
        }
    }
}
