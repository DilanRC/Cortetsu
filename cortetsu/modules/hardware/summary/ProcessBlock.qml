pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../Format.js" as Format

// The processes using the most CPU right now, most active first.
NavBlock {
    id: root

    required property var processes
    required property var memoryTotalGb
    property int maximumRows: 5

    readonly property int rowHeight: 28
    readonly property int visibleRows: Math.max(0, Math.min(
        root.processes.length,
        root.maximumRows,
        Math.floor((root.height - root.padding * 2 - label.height - header.height - 12) / root.rowHeight)))

    accessibleName: qsTr("Procesos con más consumo")

    SummaryLabel {
        id: label
        icon: "account_tree"
        text: qsTr("Mayor consumo")
    }

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: label.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        height: 18
        visible: root.visibleRows > 0

        CortetsuText {
            anchors.right: parent.right
            width: 76
            horizontalAlignment: Text.AlignRight
            text: qsTr("Memoria")
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
        }

        CortetsuText {
            anchors.right: parent.right
            anchors.rightMargin: 76
            width: 64
            horizontalAlignment: Text.AlignRight
            text: qsTr("CPU")
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom

        Repeater {
            objectName: "processRows"
            // A fixed set of rows: a reading or a change in height shows or
            // hides them, never rebuilds them.
            model: root.maximumRows

            delegate: Item {
                id: row
                required property int index
                readonly property var process: root.processes[row.index] ?? ({})

                visible: row.index < root.visibleRows
                width: parent.width
                height: root.rowHeight

                CortetsuText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 148
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.process.name ?? ""
                    textSize: CortetsuTypography.bodyPx
                    elide: Text.ElideRight
                }

                CortetsuText {
                    anchors.right: parent.right
                    anchors.rightMargin: 76
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    horizontalAlignment: Text.AlignRight
                    text: Format.withUnit(row.process.cpu, 1, "%")
                    color: CortetsuDesign.colorOnSurfaceMuted
                    textSize: CortetsuTypography.bodyPx
                }

                CortetsuText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    horizontalAlignment: Text.AlignRight
                    // The probe reports resident memory as a share of the total.
                    text: Format.known(row.process.mem) && Format.known(root.memoryTotalGb)
                        ? Format.size(Number(row.process.mem) / 100 * Number(root.memoryTotalGb))
                        : ""
                    color: CortetsuDesign.colorOnSurfaceMuted
                    textSize: CortetsuTypography.bodyPx
                }
            }
        }
    }

    CortetsuText {
        anchors.left: parent.left
        anchors.top: label.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        visible: root.processes.length === 0
        text: qsTr("La lectura no incluye procesos")
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
    }
}
