pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// One subject, one panel: a heading and the rows that belong to it. Rows
// share the panel and are told apart by a hairline, not by a card each.
ColumnLayout {
    id: root

    property string title: ""
    property string detail: ""
    default property alias rows: body.data

    Layout.fillWidth: true
    spacing: CortetsuDesign.spacingCompact

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: CortetsuDesign.spacingUnit
        Layout.rightMargin: CortetsuDesign.spacingUnit
        visible: root.title.length > 0
        spacing: CortetsuDesign.spacingCompact

        CortetsuText {
            text: root.title
            textSize: CortetsuTypography.labelLargePx
            font.weight: Font.DemiBold
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.detail
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0
        }
    }
}
