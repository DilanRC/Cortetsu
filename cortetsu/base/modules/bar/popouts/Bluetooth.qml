pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.components
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root
    readonly property string scanOwner: "bluetooth-" + String(root)

    required property PopoutState popouts

    Component.onDestruction: ConnectivityBluetooth.setScanOwner(root.scanOwner, false)
    onVisibleChanged: { if (!visible) ConnectivityBluetooth.setScanOwner(root.scanOwner, false); }

    width: 300
    spacing: CortetsuTokens.spacing.small

    CortetsuText {
        Layout.topMargin: CortetsuTokens.padding.medium
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        text: qsTr("Bluetooth")
        font: CortetsuTokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Toggle {
        label: qsTr("Enabled")
        checked: ConnectivityBluetooth.adapter?.enabled ?? false // qmllint disable unresolved-type
        toggle.onToggled: {
            const adapter = ConnectivityBluetooth.adapter; // qmllint disable unresolved-type
            if (adapter)
                ConnectivityBluetooth.setEnabled(checked);
        }
    }

    Toggle {
        label: qsTr("Discovering")
        checked: ConnectivityBluetooth.adapter?.discovering ?? false // qmllint disable unresolved-type
        toggle.onToggled: {
            const adapter = ConnectivityBluetooth.adapter; // qmllint disable unresolved-type
            if (adapter)
                ConnectivityBluetooth.setScanOwner(root.scanOwner, checked);
        }
    }

    CortetsuText {
        Layout.topMargin: CortetsuTokens.spacing.small
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        text: {
            const devices = ConnectivityBluetooth.devices; // qmllint disable unresolved-type
            let available = qsTr("%1 device%2 available").arg(devices.length).arg(devices.length === 1 ? "" : "s");
            const connected = devices.filter(d => d.connected).length;
            if (connected > 0)
                available += qsTr(" (%1 connected)").arg(connected);
            return available;
        }
        color: CortetsuColours.palette.m3onSurfaceVariant
        font: CortetsuTokens.font.body.small
    }

    Repeater {
        model: ScriptModel {
            values: [...ConnectivityBluetooth.devices].sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name)).slice(0, 5) // qmllint disable unresolved-type
        }

        RowLayout {
            id: device

            required property BluetoothDevice modelData
            readonly property bool loading: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting // qmllint disable unresolved-type

            Layout.fillWidth: true
            Layout.rightMargin: CortetsuTokens.padding.extraSmall
            spacing: CortetsuTokens.spacing.small

            opacity: 0
            scale: 0.7

            Component.onCompleted: {
                opacity = 1;
                scale = 1;
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {}
            }

            CortetsuIcon {
                text: Icons.getBluetoothIcon(device.modelData.icon)
            }

            CortetsuText {
                Layout.leftMargin: CortetsuTokens.spacing.extraSmall
                Layout.rightMargin: CortetsuTokens.spacing.extraSmall
                Layout.fillWidth: true
                text: device.modelData.name
                elide: Text.ElideRight
            }

            CortetsuIcon {
                visible: device.modelData.state === BluetoothDeviceState.Connected  // qmllint disable unresolved-type
                text: device.modelData.batteryAvailable ? Icons.getBatteryIcon(device.modelData.battery) : "battery_alert"
                color: device.modelData.batteryAvailable && device.modelData.battery < 0.2 ? CortetsuColours.palette.m3error : CortetsuColours.palette.m3onSurfaceVariant
            }

            CortetsuSurface {
                id: connectBtn

                implicitWidth: implicitHeight
                implicitHeight: connectIcon.implicitHeight + CortetsuTokens.padding.extraSmall

                radius: CortetsuTokens.rounding.full
                color: Qt.alpha(CortetsuColours.palette.m3primary, device.modelData.state === BluetoothDeviceState.Connected ? 1 : 0) // qmllint disable unresolved-type

                CircularIndicator {
                    anchors.fill: parent
                    running: device.loading
                }

                CortetsuStateLayer {
                    color: device.modelData.state === BluetoothDeviceState.Connected ? CortetsuColours.palette.m3onPrimary : CortetsuColours.palette.m3onSurface // qmllint disable unresolved-type
                    disabled: device.loading || ConnectivityBluetooth.busy
                    onClicked: device.modelData.connected ? ConnectivityBluetooth.disconnectDevice(device.modelData) : (device.modelData.paired ? ConnectivityBluetooth.connectDevice(device.modelData) : ConnectivityBluetooth.pairDevice(device.modelData))
                }

                CortetsuIcon {
                    id: connectIcon

                    anchors.centerIn: parent
                    animate: true
                    text: device.modelData.connected ? "link_off" : "link"
                    color: device.modelData.state === BluetoothDeviceState.Connected ? CortetsuColours.palette.m3onPrimary : CortetsuColours.palette.m3onSurface // qmllint disable unresolved-type

                    opacity: device.loading ? 0 : 1

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            Loader {
                visible: status === Loader.Ready
                asynchronous: true
                active: device.modelData.bonded
                sourceComponent: Item {
                    implicitWidth: connectBtn.implicitWidth
                    implicitHeight: connectBtn.implicitHeight

                    CortetsuStateLayer {
                        radius: CortetsuTokens.rounding.full
                        onClicked: ConnectivityBluetooth.forgetDevice(device.modelData)
                    }

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "delete"
                    }
                }
            }
        }
    }

    IconTextButton {
        Layout.fillWidth: true
        Layout.topMargin: CortetsuTokens.spacing.medium
        inactiveColour: CortetsuColours.palette.m3primaryContainer
        inactiveOnColour: CortetsuColours.palette.m3onPrimaryContainer
        verticalPadding: CortetsuTokens.padding.extraSmall
        text: qsTr("Open settings")
        icon: "settings"

        onClicked: root.popouts.detachRequested("bluetooth")
    }

    component Toggle: RowLayout {
        required property string label
        property alias checked: toggle.checked
        property alias toggle: toggle

        Layout.fillWidth: true
        Layout.rightMargin: CortetsuTokens.padding.extraSmall
        spacing: CortetsuTokens.spacing.medium

        CortetsuText {
            Layout.fillWidth: true
            text: parent.label
        }

        StyledSwitch {
            id: toggle
        }
    }
}
