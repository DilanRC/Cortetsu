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
    readonly property real batteryValue: {
        const device = UPower.displayDevice;
        const value = Number(device?.percentage);
        return device && Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : -1;
    }
    readonly property bool batteryAvailable: root.batteryValue >= 0
    readonly property bool laptopBatteryAvailable: UPower.displayDevice?.isLaptopBattery === true
        && root.batteryAvailable
    readonly property int batteryPercent: root.batteryAvailable ? Math.round(root.batteryValue * 100) : -1
    readonly property string networkName: CortetsuNetwork.active?.ssid
        ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : qsTr("Offline"))
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Connecting")
        : CortetsuNetwork.active
            ? qsTr("Signal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Wired connection")
                : qsTr("Network unavailable")
    readonly property bool markPressed: soundTile.pressed || dndTile.pressed || bluetoothTile.pressed
    readonly property bool markIntent: markPressed
        || soundTile.hovered || soundTile.activeFocus
        || dndTile.hovered || dndTile.activeFocus
        || bluetoothTile.hovered || bluetoothTile.activeFocus
    readonly property string markPhase: markPressed
        ? "Monster"
        : markIntent
            ? "Awakening"
            : "Human"

    function closeQsd(): void {
        const state = root.screenState;
        if (!state)
            return;
        state.qsdOpenedByShortcut = false;
        state.qsdEdgeHovered = false;
        state.qsdDrawerHovered = false;
        state.qsd = false;
    }

    function openSettings(): void {
        root.closeQsd();
        root.screenState.settings = true;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuEvolvingMark {
                id: signatureMark
                phase: root.markPhase
                monochrome: true
                monochromeColor: CortetsuDesign.colorWashi
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
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
                tooltipText: qsTr("Open Settings")
                onClicked: root.openSettings()
            }

            CortetsuButton {
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Close Quick Settings")
                onClicked: root.closeQsd()
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

            CortetsuActionTile {
                id: soundTile
                focus: true
                Layout.fillWidth: true
                label: CortetsuAudio.muted ? qsTr("Sound muted") : qsTr("Sound")
                detail: CortetsuAudio.muted ? qsTr("Tap to unmute") : qsTr("Volume %1%").arg(root.volumePercent)
                icon: CortetsuAudio.muted ? "volume_off" : "volume_up"
                highlighted: !CortetsuAudio.muted
                // Mute is a user-selected state, not a fault or danger.
                warning: false
                onActivated: if (CortetsuAudio.sink?.audio)
                    CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted
            }

            CortetsuActionTile {
                id: dndTile
                Layout.fillWidth: true
                label: CortetsuNotifications.dnd ? qsTr("Do Not Disturb") : qsTr("Notifications")
                detail: CortetsuNotifications.dnd ? qsTr("Silenced") : qsTr("Allowed")
                icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
                highlighted: CortetsuNotifications.dnd
                // DND is an explicit user preference, not a danger state.
                warning: false
                onActivated: CortetsuNotifications.dnd = !CortetsuNotifications.dnd
            }

            CortetsuActionTile {
                id: bluetoothTile
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

            CortetsuActionTile {
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
            onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuIcon {
                text: CortetsuAudio.muted ? "volume_off" : "volume_up"
                iconSize: CortetsuTypography.iconSmallPx
                // Mute is a selected audio state, not a warning condition.
                color: CortetsuAudio.muted ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorPrimary
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
            onMoved: nextValue => CortetsuAudio.setVolume(nextValue)
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
                        text: root.laptopBatteryAvailable
                            ? qsTr("Battery %1%").arg(root.batteryPercent)
                            : UPower.displayDevice?.isLaptopBattery
                                ? qsTr("Battery unavailable")
                                : UPower.displayDevice
                                    ? qsTr("External power")
                                    : qsTr("Power unavailable")
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
