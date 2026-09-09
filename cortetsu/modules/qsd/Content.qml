pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "../../components"
import ".."
import "../../services"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var screenState
    required property ShellScreen screen

    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? -1
    readonly property bool bluetoothEnabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property int connectedBluetoothCount: (Bluetooth.devices?.values ?? []).filter(device => device.connected).length
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property int batteryPercent: Math.round(UPower.displayDevice.percentage * 100)
    readonly property string networkName: CortetsuNetwork.active?.ssid
        ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : qsTr("Offline"))
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Connecting")
        : CortetsuNetwork.active
            ? qsTr("Signal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Wired connection")
                : qsTr("Network unavailable")

    function openSettings(): void {
        root.screenState.qsd = false;
        root.screenState.settings = true;
    }

    component QuickTile: CortetsuSurface {
        id: tile

        required property string label
        required property string icon
        property string detail: ""
        property bool highlighted: false
        property bool warning: false
        property bool clickable: true
        signal activated()

        implicitHeight: 76
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.10)
            : highlighted
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.64)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
        hoverColor: warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.16)
            : highlighted
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.82)
                : Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.92)
        outlineColor: warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.44)
            : highlighted
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.38)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)
        outlined: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: tile.icon
                iconSize: CortetsuTypography.iconMediumPx
                color: tile.warning
                    ? CortetsuDesign.colorWarning
                    : tile.highlighted
                        ? CortetsuDesign.colorPrimary
                        : CortetsuDesign.colorOnSurface
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                CortetsuText {
                    Layout.fillWidth: true
                    text: tile.label
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: tile.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: tile.clickable
            hoverEnabled: true
            cursorShape: tile.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: tile.hovered = true
            onExited: {
                tile.hovered = false;
                tile.pressed = false;
            }
            onPressedChanged: tile.pressed = pressed
            onClicked: tile.activated()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            Image {
                source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")
                sourceSize.width: 24
                sourceSize.height: 24
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    text: qsTr("Cortetsu")
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    text: qsTr("Quick Settings")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            CortetsuButton {
                compact: true
                icon: "settings"
                label: ""
                onClicked: root.openSettings()
            }

            CortetsuButton {
                compact: true
                icon: "close"
                label: ""
                onClicked: root.screenState.qsd = false
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Controls")
            detail: qsTr("Live system state")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: CortetsuDesign.spacingCompact
            columnSpacing: CortetsuDesign.spacingCompact

            QuickTile {
                Layout.fillWidth: true
                label: CortetsuAudio.muted ? qsTr("Sound muted") : qsTr("Sound")
                detail: CortetsuAudio.muted ? qsTr("Tap to unmute") : qsTr("Volume %1%").arg(root.volumePercent)
                icon: CortetsuAudio.muted ? "volume_off" : "volume_up"
                highlighted: !CortetsuAudio.muted
                warning: CortetsuAudio.muted
                onActivated: if (CortetsuAudio.sink?.audio)
                    CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted
            }

            QuickTile {
                Layout.fillWidth: true
                label: CortetsuNotifications.dnd ? qsTr("Do Not Disturb") : qsTr("Notifications")
                detail: CortetsuNotifications.dnd ? qsTr("Silenced") : qsTr("Allowed")
                icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
                highlighted: !CortetsuNotifications.dnd
                warning: CortetsuNotifications.dnd
                onActivated: CortetsuNotifications.dnd = !CortetsuNotifications.dnd
            }

            QuickTile {
                Layout.fillWidth: true
                label: qsTr("Bluetooth")
                detail: root.bluetoothEnabled
                    ? root.connectedBluetoothCount > 0
                        ? qsTr("%1 connected").arg(root.connectedBluetoothCount)
                        : qsTr("Ready")
                    : qsTr("Off")
                icon: root.connectedBluetoothCount > 0 ? "bluetooth_connected" : "bluetooth"
                highlighted: root.bluetoothEnabled
                clickable: Bluetooth.defaultAdapter !== null
                onActivated: if (Bluetooth.defaultAdapter)
                    Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
            }

            QuickTile {
                Layout.fillWidth: true
                label: root.networkName
                detail: root.networkDetail
                icon: CortetsuNetwork.activeEthernet
                    ? "cable"
                    : CortetsuNetwork.connecting
                        ? "sync"
                        : CortetsuNetwork.active
                            ? "wifi"
                            : "wifi_off"
                highlighted: !!CortetsuNetwork.active || !!CortetsuNetwork.activeEthernet
                warning: !CortetsuNetwork.active && !CortetsuNetwork.activeEthernet && !CortetsuNetwork.connecting
                clickable: false
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Levels")
            detail: qsTr("Hardware readback")
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuIcon {
                text: "brightness_6"
                iconSize: CortetsuTypography.iconSmallPx
                color: root.brightnessValue < 0 ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorPrimary
            }
            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Brightness")
                textSize: CortetsuTypography.labelMediumPx
            }
            CortetsuText {
                text: root.brightnessValue < 0 ? qsTr("Unavailable") : qsTr("%1%").arg(Math.round(root.brightnessValue * 100))
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        CortetsuSlider {
            Layout.fillWidth: true
            value: root.brightnessValue
            disabled: value < 0
            onMoved: root.brightnessMonitor?.setBrightness(value)
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuIcon {
                text: CortetsuAudio.muted ? "volume_off" : "volume_up"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuAudio.muted ? CortetsuDesign.colorWarning : CortetsuDesign.colorPrimary
            }
            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Volume")
                textSize: CortetsuTypography.labelMediumPx
            }
            CortetsuText {
                text: qsTr("%1%").arg(root.volumePercent)
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        CortetsuSlider {
            Layout.fillWidth: true
            value: CortetsuAudio.volume
            onMoved: CortetsuAudio.setVolume(value)
        }

        CortetsuSurface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 78
            radiusValue: CortetsuDesign.radiusLarge
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.66)
            outlined: true
            outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    CortetsuText {
                        text: qsTr("Power")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        text: UPower.displayDevice?.isLaptopBattery
                            ? qsTr("Battery %1%").arg(root.batteryPercent)
                            : qsTr("External power")
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    CortetsuText {
                        text: qsTr("Connection")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.networkName
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
