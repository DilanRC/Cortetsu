import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

// One reading in a strip of facts: what it is, above the value. Text only,
// with an optional glyph; it is not a control and takes no focus. A value
// the system does not report is written as such by the caller, never as 0.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string value: ""
    property color valueColor: CortetsuDesign.colorOnSurface

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: `${root.label}: ${root.value}`

    Row {
        id: row
        width: root.width
        spacing: CortetsuDesign.spacingCompact

        CortetsuIcon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon.length > 0
            text: root.icon
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        Column {
            width: Math.max(0, root.width - (glyph.visible ? glyph.width + row.spacing : 0))
            spacing: 1

            CortetsuText {
                width: parent.width
                text: root.label
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }

            CortetsuText {
                width: parent.width
                text: root.value
                textSize: CortetsuTypography.bodySmallPx
                font.weight: Font.DemiBold
                color: root.valueColor
                elide: Text.ElideRight
            }
        }
    }
}
