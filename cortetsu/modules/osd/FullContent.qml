pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import "../../components"
import ".."
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuOverlayPolicy.js" as OverlayPolicy

Item {
    id: root

    required property var screenState
    required property ShellScreen screen

    implicitWidth: 520
    implicitHeight: body.implicitHeight

    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? -1
    readonly property bool bluetoothEnabled: Connectivity.bluetooth.enabled
    readonly property int connectedBluetoothCount: Connectivity.bluetooth.connectedCount
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property real batteryValue: CortetsuPower.value
    readonly property bool batteryAvailable: CortetsuPower.available
    readonly property bool laptopBatteryAvailable: CortetsuPower.hasBattery
    readonly property int batteryPercent: CortetsuPower.percent
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Conectando")
        : CortetsuNetwork.active
            ? qsTr("Señal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Conexión cableada")
                : qsTr("Red no disponible")
    readonly property var wifi: Connectivity.wifi
    readonly property bool wifiOperable: !!wifi.wifiDevice && wifi.hardwareEnabled
    readonly property bool microphonePresent: !!CortetsuAudio.source?.audio
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
        OverlayPolicy.open(CortetsuShellState.allStates(), root.screenState, "settings");
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

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Ajustes rápidos")
                font.family: CortetsuDesign.fontInk
                font.weight: Font.Light
                textSize: CortetsuTypography.inkLinePx
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

        CortetsuInkLabel {
            Layout.topMargin: CortetsuDesign.spacingCompact
            mark: "制"
            title: qsTr("Controles")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: CortetsuDesign.spacingCompact
            columnSpacing: CortetsuDesign.spacingCompact

            CortetsuActionTile {
                id: soundTile
                seal: "音"
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
                seal: "静"
                Layout.fillWidth: true
                label: CortetsuNotifications.dnd ? qsTr("No molestar") : qsTr("Notificaciones")
                detail: CortetsuNotifications.dnd ? qsTr("Silenciadas") : qsTr("Permitidas")
                icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
                highlighted: CortetsuNotifications.dnd
                // DND is an explicit user preference, not a danger state.
                warning: false
                onActivated: CortetsuNotifications.toggleDnd()
            }

            CortetsuActionTile {
                id: bluetoothTile
                seal: "青"
                Layout.fillWidth: true
                label: qsTr("Bluetooth")
                detail: root.bluetoothEnabled
                    ? root.connectedBluetoothCount > 0
                        ? qsTr("%1 conectados").arg(root.connectedBluetoothCount)
                        : qsTr("Listo")
                    : qsTr("Apagado")
                icon: root.connectedBluetoothCount > 0 ? "bluetooth_connected" : "bluetooth"
                highlighted: root.bluetoothEnabled
                clickable: !!Connectivity.bluetooth.adapter
                onActivated: Connectivity.bluetooth.setEnabled(!Connectivity.bluetooth.enabled)
            }

            // The radio is the action; the link it holds is the detail. A
            // machine without a Wi-Fi device, or with it blocked by its
            // switch, gets the same tile as a reading with nothing to press.
            CortetsuActionTile {
                id: networkTile
                objectName: "quickWifi"
                Layout.fillWidth: true
                label: CortetsuNetwork.activeEthernet && !CortetsuNetwork.active ? qsTr("Ethernet")
                    : root.wifi.wifiEnabled ? (CortetsuNetwork.active?.ssid ?? qsTr("Wi-Fi")) : qsTr("Wi-Fi apagado")
                detail: root.wifi.busy && root.wifi.operation.kind === "enable" ? qsTr("Aplicando…")
                    : root.wifi.operation.kind === "enable" && root.wifi.operation.state === "failed" ? root.wifi.operation.lastError
                    : !root.wifi.wifiDevice ? root.networkDetail
                    : !root.wifi.hardwareEnabled ? qsTr("Bloqueado por el interruptor del equipo")
                    : !root.wifi.wifiEnabled ? qsTr("Pulsa para encenderlo")
                    : root.networkDetail
                icon: CortetsuNetwork.activeEthernet && !CortetsuNetwork.active
                    ? "cable"
                    : CortetsuNetwork.connecting
                        ? "sync"
                        : CortetsuNetwork.active
                            ? "wifi"
                            : "wifi_off"
                highlighted: !!CortetsuNetwork.active || !!CortetsuNetwork.activeEthernet
                // Off by choice is not a fault; no link with the radio on is.
                warning: root.wifi.wifiEnabled && !CortetsuNetwork.active && !CortetsuNetwork.activeEthernet && !CortetsuNetwork.connecting
                clickable: root.wifiOperable
                onActivated: if (!root.wifi.busy) root.wifi.setEnabled(!root.wifi.wifiEnabled)
            }

            CortetsuActionTile {
                id: microphoneTile
                objectName: "quickMicrophone"
                Layout.fillWidth: true
                label: !root.microphonePresent ? qsTr("Sin micrófono")
                    : CortetsuAudio.sourceMuted ? qsTr("Micrófono silenciado") : qsTr("Micrófono")
                detail: !root.microphonePresent ? qsTr("No hay una entrada de audio")
                    : CortetsuAudio.sourceMuted ? qsTr("Pulsa para reactivarlo")
                    : (CortetsuAudio.source?.description ?? qsTr("Entrada activa"))
                icon: root.microphonePresent && !CortetsuAudio.sourceMuted ? "mic" : "mic_off"
                highlighted: root.microphonePresent && !CortetsuAudio.sourceMuted
                warning: false
                clickable: root.microphonePresent
                onActivated: if (CortetsuAudio.source?.audio)
                    CortetsuAudio.source.audio.muted = !CortetsuAudio.source.audio.muted
            }

            CortetsuActionTile {
                Layout.fillWidth: true
                seal: "録"
                label: CortetsuRecorder.running ? qsTr("Detener grabación") : qsTr("Grabar pantalla")
                detail: CortetsuRecorder.running ? qsTr("Grabando") : qsTr("Iniciar captura")
                icon: CortetsuRecorder.running ? "stop_circle" : "radio_button_checked"
                highlighted: CortetsuRecorder.running
                warning: false
                onActivated: CortetsuRecorder.running ? CortetsuRecorder.stop() : CortetsuRecorder.start()
            }

            CortetsuActionTile {
                Layout.fillWidth: true
                seal: "醒"
                label: CortetsuIdleInhibitor.enabled ? qsTr("Permitir reposo") : qsTr("Mantener activo")
                detail: CortetsuIdleInhibitor.enabled ? qsTr("Desactivado") : qsTr("Activo mientras trabajas")
                icon: CortetsuIdleInhibitor.enabled ? "bedtime" : "bedtime_off"
                highlighted: CortetsuIdleInhibitor.enabled
                warning: false
                onActivated: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
            }

            CortetsuActionTile {
                Layout.fillWidth: true
                seal: "遊"
                label: GameMode.enabled ? qsTr("Desactivar modo juego") : qsTr("Activar modo juego")
                detail: GameMode.busy ? qsTr("Un momento…")
                    : GameMode.needsRecovery ? qsTr("Error al aplicar: pulsa para restaurar")
                    : GameMode.status === "UNKNOWN" ? qsTr("Estado desconocido: ver docs/GAME_MODE.md")
                    : GameMode.enabled ? qsTr("Efectos reducidos") : qsTr("Menos animaciones y efectos")
                icon: GameMode.enabled ? "sports_esports" : "videogame_asset"
                highlighted: GameMode.enabled
                warning: GameMode.needsRecovery
                onActivated: GameMode.toggle()
            }
        }

        CortetsuInkLabel {
            Layout.topMargin: CortetsuDesign.spacingCompact
            mark: "量"
            title: qsTr("Niveles")
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
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                text: root.brightnessValue < 0 ? qsTr("No disponible") : qsTr("%1%").arg(Math.round(root.brightnessValue * 100))
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        CortetsuSlider {
            Layout.fillWidth: true
            accessibleName: qsTr("Brillo")
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
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                text: qsTr("%1%").arg(root.volumePercent)
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        CortetsuSlider {
            Layout.fillWidth: true
            accessibleName: qsTr("Volumen")
            value: CortetsuAudio.volume
            onMoved: nextValue => CortetsuAudio.setVolume(nextValue)
        }

        // Energy as a margin note under a brush rule.
        CortetsuBrushStroke {
            Layout.fillWidth: true
            Layout.topMargin: CortetsuDesign.spacingCompact
            Layout.preferredHeight: 3
            ink: CortetsuDesign.colorWashi
            inkAlpha: 0.1
        }

        // Energy as one margin note; the connection is already its tile.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            CortetsuInkLabel { mark: "電"; title: qsTr("Energía") }
            CortetsuText {
                objectName: "quickEnergy"
                Layout.fillWidth: true
                text: root.laptopBatteryAvailable
                    ? qsTr("Batería %1%").arg(root.batteryPercent)
                    : CortetsuPower.laptopBattery
                        ? qsTr("Batería no disponible")
                        : CortetsuPower.devicePresent
                            ? qsTr("Alimentación externa")
                            : qsTr("Energía no disponible")
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }
}
