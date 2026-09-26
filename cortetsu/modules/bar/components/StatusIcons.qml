import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../.."
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography

Rectangle {
    id: root

    property color colour: CortetsuDesign.colorSecondary
    readonly property alias items: iconColumn
    readonly property int spacing: 4

    implicitWidth: 72
    implicitHeight: iconColumn.implicitHeight + 20
    radius: height / 2
    color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.82)
    border.color: CortetsuDesign.colorOutlineVariant
    border.width: 1
    clip: true

    ColumnLayout {
        id: iconColumn
        anchors.centerIn: parent
        spacing: root.spacing

        Repeater {
            model: ["audio", "microphone", "network", "bluetooth", "battery"]

            delegate: Item {
                required property string modelData
                property string name: modelData
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: indicator.implicitWidth
                implicitHeight: indicator.implicitHeight

                Text {
                    id: indicator
                    text: {
                        if (modelData === "audio")
                            return CortetsuAudio.muted ? "󰖁" : "󰕾";
                        if (modelData === "microphone")
                            return CortetsuAudio.sourceMuted ? "󰍭" : "󰍬";
                        if (modelData === "network")
                            return CortetsuNetwork.activeEthernet ? "󰈀" : (CortetsuNetwork.active ? "󰖩" : "󰖪");
                        if (modelData === "bluetooth")
                            return !Bluetooth.defaultAdapter?.enabled ? "󰂲" : (Bluetooth.devices.values.some(d => d.connected) ? "󰂱" : "󰂯");
                        if (!CortetsuPower.hasBattery)
                            return "󰁹";
                        return CortetsuPower.value > 0.2 ? "󰁹" : "󰂃";
                    }
                    color: root.colour
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: CortetsuTypography.iconMediumPx
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
