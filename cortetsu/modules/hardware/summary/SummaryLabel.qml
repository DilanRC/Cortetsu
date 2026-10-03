import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// Heading of a summary block: what it measures and, when it helps, which device.
Row {
    id: root

    property string icon: ""
    property string text: ""
    property string detail: ""

    anchors.left: parent.left
    anchors.right: parent.right
    // Leaves the corner free for the destination hint of the block.
    anchors.rightMargin: 112
    height: 20
    spacing: CortetsuDesign.spacingCompact

    CortetsuIcon {
        id: labelIcon
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: CortetsuDesign.colorOnSurfaceMuted
        iconSize: CortetsuTypography.iconSmallPx
    }

    CortetsuText {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: CortetsuDesign.colorOnSurfaceMuted
        textSize: CortetsuTypography.labelLargePx
        font.weight: Font.DemiBold
    }

    CortetsuText {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.width - labelIcon.width - labelText.width - root.spacing * 2)
        text: root.detail
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.labelMediumPx
        elide: Text.ElideRight
    }
}
