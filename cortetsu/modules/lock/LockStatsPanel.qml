pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../services"
import "../../theme"
import "../../utils"
import ".."
import "../desktop" as Desktop
import "../CortetsuTypography.js" as CortetsuTypography

// The machine, under the password (Nebula's stats panel): battery, network
// and keyboard as facts, CPU and memory as rings. Only real readings: a
// probe that has not answered shows its ring empty. Probes run only while
// the lock is on screen.
Item {
    id: root

    property string batteryLabel: ""
    property string networkLabel: ""
    property string keyboardLabel: ""
    property bool live: visible

    implicitWidth: row.implicitWidth + 48
    implicitHeight: row.implicitHeight + 32

    Desktop.ServiceUse { target: Cpu; active: root.live }
    Desktop.ServiceUse { target: Memory; active: root.live }

    Rectangle {
        anchors.fill: parent
        radius: 28
        color: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.7)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.10)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 28

        ColumnLayout {
            spacing: 10
            Repeater {
                model: [
                    { icon: CortetsuPower.hasBattery ? Icons.getBatteryIcon(CortetsuPower.value, CortetsuPower.charging) : "power", text: root.batteryLabel },
                    { icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.active ? "wifi" : "wifi_off"), text: root.networkLabel },
                    { icon: "keyboard", text: root.keyboardLabel }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: CortetsuDesign.spacingStandard
                    CortetsuIcon { text: parent.modelData.icon; iconSize: CortetsuTypography.iconMediumPx; color: CortetsuDesign.colorOnSurface }
                    CortetsuText {
                        Layout.maximumWidth: 200
                        text: parent.modelData.text
                        textSize: CortetsuTypography.bodySmallPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.alpha(CortetsuDesign.colorWashi, 0.12) }

        CortetsuRingGauge {
            Layout.preferredWidth: 84
            Layout.preferredHeight: 84
            value: Cpu.consumers > 0 && Cpu.percentage >= 0 ? Cpu.percentage : -1
            label: qsTr("CPU")
        }
        CortetsuRingGauge {
            Layout.preferredWidth: 84
            Layout.preferredHeight: 84
            value: Memory.total > 0 ? Memory.percentage : -1
            label: qsTr("RAM")
        }
    }
}
