pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import "../../components"
import ".."
import "../../services"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var screenState
    required property ShellScreen screen

    implicitWidth: 520
    implicitHeight: body.implicitHeight

    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? -1
    readonly property bool bluetoothEnabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property int connectedBluetoothCount: (Bluetooth.devices?.values ?? []).filter(device => device.connected).length
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property real batteryValue: CortetsuPower.value
    readonly property bool batteryAvailable: CortetsuPower.available
    readonly property bool laptopBatteryAvailable: CortetsuPower.hasBattery
    readonly property int batteryPercent: CortetsuPower.percent
    readonly property string networkName: CortetsuNetwork.active?.ssid
        ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : qsTr("Sin conexión"))
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Conectando")
        : CortetsuNetwork.active
            ? qsTr("Señal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Conexión cableada")
                : qsTr("Red no disponible")
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
        state.osd = false;
    }

    function openSettings(): void {
        root.closeQsd();
        root.screenState.settings = true;
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuEvolvingMark {
                id: signatureMark
                phase: root.markPhase
                monochrome: true
                monochromeColor: CortetsuDesign.colorWashi
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
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
                    text: qsTr("Ajustes rápidos")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            CortetsuButton {
                compact: true
                icon: "settings"
                label: ""
                tooltipText: qsTr("Abrir ajustes")
                onClicked: root.openSettings()
            }

            CortetsuButton {
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Cerrar ajustes rápidos")
                onClicked: root.closeQsd()
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Controles")
            detail: qsTr("Estado actual del sistema")
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
                label: CortetsuAudio.muted ? qsTr("Sonido silenciado") : qsTr("Sonido")
                detail: CortetsuAudio.muted ? qsTr("Pulsa para activar el sonido") : qsTr("Volumen %1%").arg(root.volumePercent)
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
                label: CortetsuNotifications.dnd ? qsTr("No molestar") : qsTr("Notificaciones")
                detail: CortetsuNotifications.dnd ? qsTr("Silenciadas") : qsTr("Permitidas")
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
                        ? qsTr("%1 conectados").arg(root.connectedBluetoothCount)
                        : qsTr("Listo")
                    : qsTr("Apagado")
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

            CortetsuActionTile {
                Layout.fillWidth: true
                label: CortetsuRecorder.running ? qsTr("Detener grabación") : qsTr("Grabar pantalla")
                detail: CortetsuRecorder.running ? qsTr("Grabando") : qsTr("Iniciar captura")
                icon: CortetsuRecorder.running ? "stop_circle" : "radio_button_checked"
                highlighted: CortetsuRecorder.running
                warning: false
                onActivated: CortetsuRecorder.running ? CortetsuRecorder.stop() : CortetsuRecorder.start()
            }

            CortetsuActionTile {
                Layout.fillWidth: true
                label: CortetsuIdleInhibitor.enabled ? qsTr("Permitir reposo") : qsTr("Mantener activo")
                detail: CortetsuIdleInhibitor.enabled ? qsTr("Desactivado") : qsTr("Activo mientras trabajas")
                icon: CortetsuIdleInhibitor.enabled ? "bedtime" : "bedtime_off"
                highlighted: CortetsuIdleInhibitor.enabled
                warning: false
                onActivated: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
            }

            CortetsuActionTile {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                label: GameMode.enabled ? qsTr("Desactivar modo juego") : qsTr("Activar modo juego")
                detail: GameMode.enabled ? qsTr("Efectos reducidos") : qsTr("Menos animaciones y efectos")
                icon: GameMode.enabled ? "sports_esports" : "videogame_asset"
                highlighted: GameMode.enabled
                warning: false
                onActivated: GameMode.toggle()
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Niveles")
            detail: qsTr("Lectura del hardware")
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
                text: qsTr("Brillo")
                textSize: CortetsuTypography.labelMediumPx
            }
            CortetsuText {
                text: root.brightnessValue < 0 ? qsTr("No disponible") : qsTr("%1%").arg(Math.round(root.brightnessValue * 100))
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
                text: qsTr("Volumen")
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
            Layout.preferredHeight: 78
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
                        text: qsTr("Energía")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        text: root.laptopBatteryAvailable
                            ? qsTr("Batería %1%").arg(root.batteryPercent)
                            : CortetsuPower.laptopBattery
                                ? qsTr("Batería no disponible")
                                : CortetsuPower.devicePresent
                                    ? qsTr("Alimentación externa")
                                    : qsTr("Energía no disponible")
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
                        text: qsTr("Conexión")
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
