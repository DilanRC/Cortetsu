pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Network rate: the figure in ink, the direction as a label.
ColumnLayout {
    id: rate
    property real value
    property string label
    readonly property var f: NetworkUsage.formatBytesRate(value)
    spacing: 0
    RowLayout {
        spacing: 4
        DashInk { text: rate.f.value.toFixed(1); textSize: CortetsuTypography.inkTitlePx }
        CortetsuText { Layout.alignment: Qt.AlignBaseline; text: `${rate.f.unit}/s`; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
    }
    DashLabel { text: rate.label }
}
