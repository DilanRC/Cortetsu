pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothAdapter adapter: ConnectivityBluetooth.adapter // qmllint disable unresolved-type
    readonly property bool btEnabled: adapter?.enabled ?? false

    title: qsTr("Connected devices")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Bluetooth")
            font: CortetsuTokens.font.body.medium
            horizontalPadding: CortetsuTokens.padding.largeIncreased
            checked: root.btEnabled
            onToggled: {
                if (root.adapter)
                    ConnectivityBluetooth.setEnabled(checked);
            }
        }

        ItemList {
            id: savedList

            showList: root.btEnabled
            placeholderIcon: root.btEnabled ? "devices_other" : "bluetooth_disabled"
            placeholderText: root.btEnabled ? qsTr("No saved devices") : qsTr("Bluetooth disabled")

            model: ScriptModel {
                values: ConnectivityBluetooth.devices.filter(d => d.bonded).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)) // qmllint disable unresolved-type
            }

            delegate: CortetsuSurface {
                id: device

                required property BluetoothDevice modelData
                readonly property bool connected: modelData && modelData.state === BluetoothDeviceState.Connected // qmllint disable unresolved-type
                readonly property bool loading: modelData && (modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting) // qmllint disable unresolved-type
                property real textOpacity: loading ? 0.5 : 1

                anchors.left: savedList.list.contentItem.left
                anchors.right: savedList.list.contentItem.right
                implicitHeight: deviceLayout.implicitHeight + deviceLayout.anchors.margins * 2
                radius: CortetsuTokens.rounding.extraSmall
                color: "transparent"

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                CortetsuStateLayer {
                    disabled: device.loading || ConnectivityBluetooth.busy
                    onClicked: {
                        if (!device.modelData || device.loading)
                            return;
                        device.connected ? ConnectivityBluetooth.disconnectDevice(device.modelData) : ConnectivityBluetooth.connectDevice(device.modelData);
                    }
                }

                RowLayout {
                    id: deviceLayout

                    anchors.fill: parent
                    anchors.margins: CortetsuTokens.padding.medium
                    anchors.leftMargin: CortetsuTokens.padding.largeIncreased
                    anchors.rightMargin: CortetsuTokens.padding.largeIncreased
                    spacing: CortetsuTokens.spacing.medium

                    CortetsuSurface {
                        implicitWidth: implicitHeight
                        implicitHeight: deviceIcon.implicitHeight + CortetsuTokens.padding.small * 2
                        radius: CortetsuTokens.rounding.full
                        color: device.connected ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3secondaryContainer

                        CortetsuIcon {
                            id: deviceIcon

                            anchors.centerIn: parent
                            text: Icons.getBluetoothIcon(device.modelData?.icon ?? "")
                            color: device.connected ? CortetsuColours.palette.m3onPrimary : CortetsuColours.palette.m3onSecondaryContainer
                            fontStyle: CortetsuTokens.font.icon.medium
                            fill: device.connected ? 1 : 0
                            opacity: device.textOpacity

                            Behavior on fill {
                                Anim {}
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: device.textOpacity

                        CortetsuText {
                            Layout.fillWidth: true
                            text: device.modelData?.name ?? qsTr("Unknown")
                            font: CortetsuTokens.font.body.small
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            Layout.fillWidth: true
                            text: device.connected ? qsTr("Connected%1").arg(device.modelData?.batteryAvailable ? " • " + Math.round(device.modelData.battery * 100) + "%" : "") : qsTr("Saved")
                            color: CortetsuColours.palette.m3outline
                            font: CortetsuTokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        implicitWidth: height

                        AnimLoader {
                            anchors.centerIn: parent
                            sourceComp: device.loading ? loadingComp : btnComp

                            Component {
                                id: btnComp

                                IconButton {
                                    icon: "settings"
                                    type: IconButton.Text
                                    padding: CortetsuTokens.padding.small
                                    inactiveOnColour: device.connected ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3onSurfaceVariant
                                    label.fill: 0

                                    onClicked: {
                                        root.nState.selectedBtDevice = device.modelData;
                                        root.nState.openSubPage(1); // Per device info page
                                    }
                                }
                            }

                            Component {
                                id: loadingComp

                                LoadingIndicator {
                                    implicitSize: Math.round(CortetsuTokens.font.icon.medium.pointSize * 1.3)
                                }
                            }
                        }
                    }
                }
            }
        }

        RowButton {
            last: true
            icon: "add"
            text: qsTr("Pair new device")
            disabled: !root.btEnabled
            onClicked: root.nState.openSubPage(2)
        }

        ToggleRow {
            Layout.topMargin: CortetsuTokens.spacing.large - parent.spacing

            first: true
            text: qsTr("Discoverable")
            subtext: qsTr("Allow nearby devices to find this one")
            disabled: !root.btEnabled
            checked: root.adapter?.discoverable ?? false
            onToggled: {
                if (root.adapter)
                    ConnectivityBluetooth.setDiscoverable(checked);
            }

            Behavior on opacity {
                Anim {}
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Pairable")
            subtext: qsTr("Allow nearby devices to pair with this one")
            disabled: !root.btEnabled
            checked: root.adapter?.pairable ?? false
            onToggled: {
                if (root.adapter)
                    ConnectivityBluetooth.setPairable(checked);
            }

            Behavior on opacity {
                Anim {}
            }
        }
    }
}
