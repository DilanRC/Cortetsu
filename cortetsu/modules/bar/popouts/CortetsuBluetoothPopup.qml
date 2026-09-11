pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../../services"
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../.."

CortetsuPopupSurface {
    id: root

    required property var popouts
    implicitWidth: 336
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property bool adapterEnabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property var devices: [...Bluetooth.devices.values].sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property int connectedCount: root.devices.filter(device => device.connected).length

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            title: qsTr("Bluetooth")
            detail: root.adapterEnabled
                ? root.connectedCount > 0
                    ? qsTr("%1 connected").arg(root.connectedCount)
                    : qsTr("Ready")
                : qsTr("Off")
        }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 64
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: root.adapterEnabled
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.52)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.74)
            outlineColor: root.adapterEnabled
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.28)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
            outlined: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                Item {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusSmall
                        baseColor: root.adapterEnabled
                            ? Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.7)
                    }

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: root.connectedCount > 0 ? "bluetooth_connected" : "bluetooth"
                        iconSize: CortetsuDesign.iconMediumPx + 4
                        color: root.adapterEnabled
                            ? CortetsuDesign.colorPrimary
                            : CortetsuDesign.colorOnSurfaceMuted
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.adapterEnabled ? qsTr("Bluetooth enabled") : qsTr("Bluetooth disabled")
                        textSize: CortetsuDesign.bodySmallPx
                        color: CortetsuDesign.colorOnSurface
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.adapterEnabled
                            ? qsTr("Choose a device below")
                            : qsTr("Turn it on to connect devices")
                        textSize: CortetsuDesign.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }

                CortetsuToggle {
                    checked: root.adapterEnabled
                    disabled: !Bluetooth.defaultAdapter
                    onToggled: checked => {
                        if (Bluetooth.defaultAdapter)
                            Bluetooth.defaultAdapter.enabled = checked;
                    }
                }
            }
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: !root.adapterEnabled || root.devices.length === 0
            kind: root.adapterEnabled ? "empty" : "error"
            title: root.adapterEnabled ? qsTr("No devices nearby") : qsTr("Bluetooth is off")
            detail: root.adapterEnabled
                ? qsTr("Paired and discovered devices will appear here")
                : qsTr("Enable Bluetooth to connect devices")
        }

        CortetsuSectionHeader {
            visible: root.adapterEnabled && root.devices.length > 0
            title: qsTr("Devices")
            detail: qsTr("%1 available").arg(root.devices.length)
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 5 * CortetsuDesign.rowHeight)
            visible: root.adapterEnabled && root.devices.length > 0
            clip: true
            spacing: CortetsuDesign.spacingUnit
            model: root.devices
            delegate: CortetsuListRow {
                required property BluetoothDevice modelData
                width: ListView.view.width
                icon: modelData.connected ? "bluetooth_connected" : "bluetooth"
                title: modelData.name ?? qsTr("Unknown device")
                subtitle: modelData.connected
                    ? qsTr("Connected · activate to disconnect")
                    : modelData.paired
                        ? qsTr("Paired · activate to connect")
                        : qsTr("Available")
                selected: modelData.connected
                onClicked: {
                    if (modelData.connected)
                        modelData.disconnect();
                    else
                        modelData.connect();
                }
            }
        }
    }
}
