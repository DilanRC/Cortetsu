pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.components
import qs.utils
import qs.services

Item {
    id: root

    required property color colour

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    Behavior on implicitHeight {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    ColumnLayout {
        id: layout

        spacing: CortetsuTokens.spacing.medium / 2

        // Bluetooth icon
        CortetsuIcon {
            animate: true
            text: {
                if (ConnectivityBluetooth.connectedCount > 0)
                    return "bluetooth_connected";
                if (!ConnectivityBluetooth.enabled)
                    return "bluetooth_disabled";
                return "bluetooth";
            }
            color: root.colour
        }

        // Connected bluetooth devices
        Repeater {
            model: ScriptModel {
                values: ConnectivityBluetooth.allDevices.filter(d => d.state !== BluetoothDeviceState.Disconnected) // qmllint disable unresolved-type
            }

            CortetsuIcon {
                id: device

                required property BluetoothDevice modelData

                animate: true
                text: Icons.getBluetoothIcon(modelData?.icon)
                color: root.colour
                fill: 1

                SequentialAnimation on opacity {
                    running: device.modelData?.state !== BluetoothDeviceState.Connected // qmllint disable unresolved-type
                    alwaysRunToEnd: true
                    loops: Animation.Infinite

                    Anim {
                        from: 1
                        to: 0
                        duration: CortetsuTokens.anim.durations.large
                        easing: CortetsuTokens.anim.standardAccel
                    }
                    Anim {
                        from: 0
                        to: 1
                        duration: CortetsuTokens.anim.durations.large
                        easing: CortetsuTokens.anim.standardDecel
                    }
                }
            }
        }
    }
}
