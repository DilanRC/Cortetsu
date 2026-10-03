pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothDevice device: nState.selectedBtDevice
    readonly property bool connected: device?.state === BluetoothDeviceState.Connected // qmllint disable unresolved-type
    readonly property bool loading: device?.state === BluetoothDeviceState.Connecting || device?.state === BluetoothDeviceState.Disconnecting // qmllint disable unresolved-type

    readonly property string statusText: {
        if (!device)
            return "";
        let s = connected ? qsTr("Connected") : (device.bonded ? qsTr("Paired") : qsTr("Not paired"));
        if (connected && device.batteryAvailable)
            s += " • " + Math.round(device.battery * 100) + "%";
        return s;
    }

    onDeviceChanged: {
        // Auto close when device lost
        if (!device)
            nState.closeSubPage();
    }

    title: device?.name ?? qsTr("Device")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        // Big buttons
        ButtonRow {
            Layout.bottomMargin: CortetsuTokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * 0.7)
            spacing: CortetsuTokens.spacing.small

            ButtonBase {
                id: forgetBtn
                stateLayer.disabled: ConnectivityBluetooth.busy

                fillWidth: true
                shapeMorph: true
                isRound: true

                inactiveColour: CortetsuColours.palette.m3errorContainer
                inactiveOnColour: CortetsuColours.palette.m3onErrorContainer

                implicitWidth: forgetBtnLayout.implicitWidth + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: forgetBtnLayout.implicitHeight + CortetsuTokens.padding.medium * 2

                onClicked: {
                    ConnectivityBluetooth.forgetDevice(root.device);
                }

                ColumnLayout {
                    id: forgetBtnLayout

                    anchors.centerIn: parent
                    spacing: 0

                    CortetsuIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "delete"
                        color: forgetBtn.onColour
                        fontStyle: CortetsuTokens.font.icon.medium
                    }

                    CortetsuText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Forget")
                        color: forgetBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: connectBtn

                fillWidth: true
                shapeMorph: true
                isRound: true

                inactiveColour: CortetsuColours.palette.m3primaryContainer
                inactiveOnColour: CortetsuColours.palette.m3onPrimaryContainer
                stateLayer.disabled: root.loading || ConnectivityBluetooth.busy

                implicitWidth: connectBtnContent.implicitWidth + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: connectBtnContent.implicitHeight + CortetsuTokens.padding.medium * 2

                onClicked: root.connected ? ConnectivityBluetooth.disconnectDevice(root.device) : ConnectivityBluetooth.connectDevice(root.device)

                AnimLoader {
                    id: connectBtnContent

                    anchors.centerIn: parent
                    sourceComp: root.loading ? loadingComp : textComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: loadingComp

                    LoadingIndicator {
                        implicitSize: connectBtn.height - CortetsuTokens.padding.large * 2
                    }
                }

                Component {
                    id: textComp

                    ColumnLayout {
                        spacing: 0

                        CortetsuIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.connected ? "close" : "add"
                            color: connectBtn.inactiveOnColour
                            fontStyle: CortetsuTokens.font.icon.medium
                            animate: true
                        }

                        CortetsuText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.connected ? qsTr("Disconnect") : qsTr("Connect")
                            color: connectBtn.inactiveOnColour
                            animate: true
                        }
                    }
                }
            }
        }

        // Connection group
        ToggleRow {
            verticalPadding: CortetsuTokens.padding.large
            first: true
            text: qsTr("Trusted")
            subtext: qsTr("Allow this device to connect automatically")
            disabled: ConnectivityBluetooth.busy
            checked: Connectivity.bluetooth.propertyValue(root.device, "trusted")
            onToggled: {
                if (root.device)
                    ConnectivityBluetooth.setTrusted(root.device, checked);
            }
        }

        ToggleRow {
            verticalPadding: CortetsuTokens.padding.large
            text: qsTr("Blocked")
            subtext: qsTr("Prevent this device from connecting")
            disabled: ConnectivityBluetooth.busy
            checked: Connectivity.bluetooth.propertyValue(root.device, "blocked")
            onToggled: {
                if (root.device)
                    ConnectivityBluetooth.setBlocked(root.device, checked);
            }
        }

        ToggleRow {
            verticalPadding: CortetsuTokens.padding.large
            last: true
            text: qsTr("Wake allowed")
            subtext: qsTr("Allow this device to wake the system")
            disabled: ConnectivityBluetooth.busy
            checked: Connectivity.bluetooth.propertyValue(root.device, "wakeAllowed")
            onToggled: {
                if (root.device)
                    ConnectivityBluetooth.setWakeAllowed(root.device, checked);
            }
        }

        // Information
        ConnectedRect {
            Layout.topMargin: CortetsuTokens.spacing.large - parent.spacing
            Layout.fillWidth: true
            implicitHeight: batteryLayout.implicitHeight + CortetsuTokens.padding.large * 2
            first: true

            ColumnLayout {
                id: batteryLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: CortetsuTokens.padding.large
                spacing: CortetsuTokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuTokens.spacing.medium

                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("Battery")
                    }

                    CortetsuText {
                        text: root.device?.batteryAvailable ? Math.round(root.device.battery * 100) + "%" : qsTr("Unavailable")
                        color: CortetsuColours.palette.m3outline
                        font: CortetsuTokens.font.body.small
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.device?.batteryAvailable ?? false
                    visible: active
                    asynchronous: true

                    sourceComponent: StyledProgressBar {
                        implicitHeight: CortetsuTokens.padding.medium
                        value: root.device.battery
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: addrLayout.implicitHeight + CortetsuTokens.padding.large * 2
            last: true

            RowLayout {
                id: addrLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: CortetsuTokens.padding.large
                spacing: CortetsuTokens.spacing.medium

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Address")
                }

                CortetsuText {
                    text: root.device?.address ?? ""
                    color: CortetsuColours.palette.m3outline
                    font: CortetsuTokens.font.body.small
                }
            }
        }
    }
}
