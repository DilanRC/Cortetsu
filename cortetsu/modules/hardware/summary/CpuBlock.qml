pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../Format.js" as Format

// Processor load now and over the last minutes.
NavBlock {
    id: root

    required property var cpu
    required property var load
    required property var history
    required property int historyLength
    required property int historySeconds
    property string temperatureSeverity: ""

    accessibleName: qsTr("CPU al %1").arg(Format.percent(root.cpu?.usage))

    SummaryLabel {
        id: label
        icon: "memory"
        text: qsTr("CPU")
        detail: root.cpu?.model ?? ""
    }

    Row {
        id: figures
        anchors.left: parent.left
        anchors.top: label.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        spacing: CortetsuDesign.spacingComfortable

        CortetsuText {
            id: usage
            objectName: "cpuUsage"
            // Width is reserved so the figures beside it hold still while the
            // value changes.
            width: 104
            text: Format.percent(root.cpu?.usage)
            textSize: CortetsuTypography.displayLargePx
            font.weight: Font.DemiBold
        }

        SummaryFacts {
            anchors.baseline: usage.baseline
            lead: Format.celsius(root.cpu?.temp_c)
            rest: Format.join([
                Format.gigahertz(root.cpu?.freq_mhz),
                root.load?.length ? qsTr("carga %1").arg(Format.fixed(root.load[0], 2)) : ""
            ])
            severity: root.temperatureSeverity
            textSize: CortetsuTypography.bodyLargePx
        }
    }

    Sparkline {
        id: line
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: figures.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        anchors.bottom: caption.top
        anchors.bottomMargin: CortetsuDesign.spacingCompact
        values: root.history
        capacity: root.historyLength
    }

    // Marks the area as a graph before it has two samples to draw.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: line.bottom
        height: 1
        color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.5)
    }

    CortetsuText {
        id: caption
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        text: qsTr("Uso en los últimos %1").arg(Format.duration(root.historySeconds))
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.labelSmallPx
    }
}
