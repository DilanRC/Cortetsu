import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import ".."
import "../CortetsuTypography.js" as CortetsuTypography

// One reading in the dashboard's system row. It has no action, so it takes
// no hover, press or focus (H-22: the list rows it replaces looked clickable).
RowLayout {
    id: root

    property string icon
    property string title
    property string subtitle

    spacing: CortetsuDesign.spacingCompact
    Accessible.role: Accessible.StaticText
    Accessible.name: `${root.title}, ${root.subtitle}`

    CortetsuIcon {
        text: root.icon
        iconSize: CortetsuTypography.iconMediumPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        CortetsuText {
            Layout.fillWidth: true
            text: root.title
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            Layout.fillWidth: true
            text: root.subtitle
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }
    }
}
