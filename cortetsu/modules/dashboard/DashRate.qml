pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

RowLayout {
    property string icon
    property real rate
    property string label
    spacing: CortetsuDesign.spacingCompact
    CortetsuIcon { text: parent.icon; color: CortetsuDesign.colorPrimary }
    ColumnLayout {
        spacing: 0
        CortetsuText {
            readonly property var f: NetworkUsage.formatBytesRate(parent.parent.rate)
            text: `${f.value.toFixed(1)} ${f.unit}/s`
            font.weight: Font.DemiBold
        }
        CortetsuText { text: parent.parent.label; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
    }
}
