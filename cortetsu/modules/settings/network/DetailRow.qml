pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography

RowLayout {
    required property string label
    required property string value
    Layout.fillWidth: true
    spacing: CortetsuDesign.spacingStandard

    CortetsuText {
        Layout.fillWidth: true
        text: parent.label
        textSize: CortetsuTypography.bodySmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    CortetsuText {
        Layout.minimumWidth: 110
        text: parent.value
        textSize: CortetsuTypography.bodySmallPx
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }
}
