pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../../components"
import ".."
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuOverlayPolicy.js" as OverlayPolicy
import "../settings" as SettingsModule

// The control center (level 2 of ADR-008): several domains at once, each
// with its frequent operation in reach and its detail on demand. Levels
// come first because they are what is touched most; the connection pair is
// next; the switches are compact; energy is one line with its profile.
// Every control here calls the owner the Hub popouts and Settings call, so
// a result or a refusal reads the same in all three.
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
    readonly property bool volumeAvailable: !!CortetsuAudio.sink?.ready && !!CortetsuAudio.sink?.audio
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
    // The device lists open on demand; the panel opens compact every time.
    property bool audioExpanded: false
    readonly property var profiles: [
        { profile: PowerProfile.PowerSaver, label: qsTr("Ahorro"), icon: "energy_savings_leaf" },
        { profile: PowerProfile.Balanced, label: qsTr("Equilibrado"), icon: "balance" }
    ].concat(PowerProfiles.hasPerformanceProfile
        ? [{ profile: PowerProfile.Performance, label: qsTr("Rendimiento"), icon: "rocket_launch" }]
        : [])
    readonly property int profileIndex: {
        for (let i = 0; i < profiles.length; ++i)
            if (profiles[i].profile === PowerProfiles.profile)
                return i;
        return -1;
    }
    readonly property string energyLine: root.laptopBatteryAvailable
        ? (CortetsuPower.charging
            ? qsTr("Batería %1% · cargando").arg(root.batteryPercent)
            : qsTr("Batería %1%").arg(root.batteryPercent))
        : CortetsuPower.laptopBattery
            ? qsTr("Batería no disponible")
            : CortetsuPower.devicePresent
                ? qsTr("Alimentación externa")
                : qsTr("Energía no disponible")

    onScreenStateChanged: root.audioExpanded = false
    Connections {
        target: root.screenState
        function onOsdChanged(): void {
            if (!root.screenState?.osd)
                root.audioExpanded = false;
        }
    }

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

    // Settings opened on one page: the control center's detail lives there.
    function openSettingsPage(page: string): void {
        SettingsModule.SettingsController.select(page);
        root.openSettings();
    }

    readonly property var player: Players.active
    // A few app streams fit here; the rest stay in Ajustes → Sonido.
    readonly property int streamsShown: 4

    // The picker opens once the panel has gone, so the panel is never in
    // the frame. A constant, not a motion token: with reduced motion the
    // tokens are 0 and the close still takes a compositor frame or two.
    function captureArea(): void {
        root.closeQsd();
        captureDelay.restart();
    }

    Timer {
        id: captureDelay
        interval: 220
        onTriggered: ShellState.shellRoot?.screenshotPicker?.open(false, false)
    }

    function nodeName(node): string {
        return node?.description || node?.nickname || node?.name || qsTr("Dispositivo sin nombre");
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: CortetsuDesign.spacingStandard

        // Identity once, small and still: the mark is the product's
        // signature here, not a reaction to the pointer.
        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuEvolvingMark {
                phase: "Ascended"
                animated: false
                monochrome: true
                monochromeColor: CortetsuDesign.colorOnSurface
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Ajustes rápidos")
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
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

        // --- Levels -------------------------------------------------------

        LevelRow {
            id: volumeRow
            Layout.fillWidth: true
            icon: CortetsuAudio.muted || !root.volumeAvailable ? "volume_off" : "volume_up"
            title: qsTr("Volumen")
            detail: root.volumeAvailable ? root.nodeName(CortetsuAudio.sink) : ""
            amount: !root.volumeAvailable ? qsTr("No disponible")
                : CortetsuAudio.muted ? qsTr("Silenciado") : `${root.volumePercent}%`
            muted: CortetsuAudio.muted
            available: root.volumeAvailable
            muteText: CortetsuAudio.muted ? qsTr("Activar el sonido") : qsTr("Silenciar")
            expandable: CortetsuAudio.sinks.length + CortetsuAudio.sources.length > 1 || CortetsuAudio.streams.length > 0
            expanded: root.audioExpanded
            onMuteRequested: if (CortetsuAudio.sink?.audio)
                CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted
            onExpandRequested: root.audioExpanded = !root.audioExpanded
        }

        CortetsuSlider {
            Layout.fillWidth: true
            accessibleName: qsTr("Volumen")
            value: CortetsuAudio.volume
            // As in Ajustes → Sonido: the limit, or the current level if
            // something outside Cortetsu set it higher.
            to: Math.max(CortetsuConfig.maxVolume, CortetsuAudio.volume)
            disabled: !root.volumeAvailable
            onMoved: nextValue => CortetsuAudio.setVolume(nextValue)
        }

        // Output and input devices and app volumes, on demand. A row is the
        // device; the selected one is the default PipeWire reports back.
        ColumnLayout {
            objectName: "quickAudioDevices"
            Layout.fillWidth: true
            visible: root.audioExpanded
            spacing: 2

            CortetsuSectionHeader {
                Layout.fillWidth: true
                visible: CortetsuAudio.sinks.length > 0
                title: qsTr("Salida")
            }
            Repeater {
                model: root.audioExpanded ? CortetsuAudio.sinks : []
                delegate: CortetsuListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    compact: true
                    icon: modelData === CortetsuAudio.sink ? "radio_button_checked" : "radio_button_unchecked"
                    title: root.nodeName(modelData)
                    selected: modelData === CortetsuAudio.sink
                    onClicked: CortetsuAudio.setAudioSink(modelData)
                }
            }

            CortetsuSectionHeader {
                Layout.fillWidth: true
                Layout.topMargin: CortetsuDesign.spacingCompact
                visible: CortetsuAudio.sources.length > 0
                title: qsTr("Entrada")
            }
            Repeater {
                model: root.audioExpanded ? CortetsuAudio.sources : []
                delegate: CortetsuListRow {
                    required property var modelData
                    Layout.fillWidth: true
                    compact: true
                    icon: modelData === CortetsuAudio.source ? "radio_button_checked" : "radio_button_unchecked"
                    title: root.nodeName(modelData)
                    selected: modelData === CortetsuAudio.source
                    onClicked: CortetsuAudio.setAudioSource(modelData)
                }
            }

            // Per-app volume, the busiest streams first in PipeWire order.
            CortetsuSectionHeader {
                Layout.fillWidth: true
                Layout.topMargin: CortetsuDesign.spacingCompact
                visible: CortetsuAudio.streams.length > 0
                title: CortetsuAudio.streams.length > root.streamsShown
                    ? qsTr("Aplicaciones · %1 de %2").arg(root.streamsShown).arg(CortetsuAudio.streams.length)
                    : qsTr("Aplicaciones")
            }
            Repeater {
                model: root.audioExpanded ? CortetsuAudio.streams.slice(0, root.streamsShown) : []
                delegate: RowLayout {
                    id: stream
                    required property var modelData
                    readonly property bool streamMuted: CortetsuAudio.getStreamMuted(modelData)
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        compact: true
                        icon: stream.streamMuted ? "volume_off" : "volume_up"
                        label: ""
                        danger: stream.streamMuted
                        tooltipText: stream.streamMuted ? qsTr("Activar %1").arg(CortetsuAudio.getStreamName(stream.modelData))
                            : qsTr("Silenciar %1").arg(CortetsuAudio.getStreamName(stream.modelData))
                        onClicked: CortetsuAudio.setStreamMuted(stream.modelData, !stream.streamMuted)
                    }
                    CortetsuText {
                        Layout.preferredWidth: 140
                        text: CortetsuAudio.getStreamName(stream.modelData)
                        textSize: CortetsuTypography.bodySmallPx
                        elide: Text.ElideRight
                    }
                    CortetsuSlider {
                        Layout.fillWidth: true
                        accessibleName: qsTr("Volumen de %1").arg(CortetsuAudio.getStreamName(stream.modelData))
                        value: CortetsuAudio.getStreamVolume(stream.modelData)
                        to: Math.max(CortetsuConfig.maxVolume, value)
                        disabled: stream.streamMuted
                        onMoved: nextValue => CortetsuAudio.setStreamVolume(stream.modelData, nextValue)
                    }
                }
            }
            CortetsuButton {
                Layout.alignment: Qt.AlignRight
                compact: true
                icon: "tune"
                label: qsTr("Sonido en Ajustes")
                tooltipText: qsTr("Dispositivos, aplicaciones, ecualizador y límites")
                onClicked: root.openSettingsPage("sound")
            }

            LevelRow {
                Layout.fillWidth: true
                Layout.topMargin: CortetsuDesign.spacingCompact
                visible: root.microphonePresent
                icon: CortetsuAudio.sourceMuted ? "mic_off" : "mic"
                title: qsTr("Nivel del micrófono")
                amount: CortetsuAudio.sourceMuted ? qsTr("Silenciado")
                    : `${Math.round(CortetsuAudio.sourceVolume * 100)}%`
                muted: CortetsuAudio.sourceMuted
                available: root.microphonePresent
                attention: CortetsuAudio.sourceMuted
                muteText: CortetsuAudio.sourceMuted ? qsTr("Reactivar el micrófono") : qsTr("Silenciar el micrófono")
                onMuteRequested: if (CortetsuAudio.source?.audio)
                    CortetsuAudio.source.audio.muted = !CortetsuAudio.source.audio.muted
            }
            CortetsuSlider {
                Layout.fillWidth: true
                visible: root.microphonePresent
                accessibleName: qsTr("Nivel del micrófono")
                value: CortetsuAudio.sourceVolume
                onMoved: nextValue => CortetsuAudio.setSourceVolume(nextValue)
            }
        }

        LevelRow {
            Layout.fillWidth: true
            Layout.topMargin: CortetsuDesign.spacingCompact
            icon: "light_mode"
            title: qsTr("Brillo")
            detail: root.brightnessValue < 0 ? qsTr("Esta pantalla no lo permite") : ""
            amount: root.brightnessValue < 0 ? qsTr("No disponible")
                : `${Math.round(root.brightnessValue * 100)}%`
            available: root.brightnessValue >= 0
            showMute: false
        }

        CortetsuSlider {
            Layout.fillWidth: true
            visible: root.brightnessValue >= 0
            accessibleName: qsTr("Brillo")
            value: Math.max(0, root.brightnessValue)
            onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)
        }

        // --- Now playing: only while a player exists -----------------------

        RowLayout {
            objectName: "quickMedia"
            Layout.fillWidth: true
            Layout.topMargin: CortetsuDesign.spacingCompact
            visible: !!root.player
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: root.player?.isPlaying ? "graphic_eq" : "music_note"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuDesign.colorPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle || qsTr("Sin título")
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackArtist || Players.getIdentity(root.player)) : ""
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
            CortetsuButton {
                compact: true; icon: "skip_previous"; label: ""
                tooltipText: qsTr("Anterior")
                disabled: !root.player?.canGoPrevious
                onClicked: root.player?.previous()
            }
            CortetsuButton {
                compact: true
                icon: root.player?.isPlaying ? "pause" : "play_arrow"
                label: ""
                tooltipText: root.player?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir")
                disabled: !root.player?.canTogglePlaying
                onClicked: root.player?.togglePlaying()
            }
            CortetsuButton {
                compact: true; icon: "skip_next"; label: ""
                tooltipText: qsTr("Siguiente")
                disabled: !root.player?.canGoNext
                onClicked: root.player?.next()
            }
        }

        CortetsuDivider { Layout.fillWidth: true; Layout.topMargin: CortetsuDesign.spacingUnit }

        // --- Connections: the two radios carry their link as detail -------

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            // The radio is the action; the link it holds is the detail. A
            // machine without a Wi-Fi device, or with it blocked by its
            // switch, gets the same tile as a reading with nothing to press.
            CortetsuActionTile {
                id: networkTile
                objectName: "quickWifi"
                focus: true
                Layout.fillWidth: true
                Layout.preferredWidth: 1
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
                id: bluetoothTile
                objectName: "quickBluetooth"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                label: qsTr("Bluetooth")
                detail: !Connectivity.bluetooth.adapter ? qsTr("Sin adaptador")
                    : root.bluetoothEnabled
                        ? root.connectedBluetoothCount === 1 ? qsTr("1 conectado")
                        : root.connectedBluetoothCount > 1 ? qsTr("%1 conectados").arg(root.connectedBluetoothCount)
                        : qsTr("Encendido")
                    : qsTr("Apagado")
                icon: root.connectedBluetoothCount > 0 ? "bluetooth_connected"
                    : root.bluetoothEnabled ? "bluetooth" : "bluetooth_disabled"
                highlighted: root.bluetoothEnabled
                warning: false
                clickable: !!Connectivity.bluetooth.adapter
                onActivated: Connectivity.bluetooth.setEnabled(!Connectivity.bluetooth.enabled)
            }
        }

        // --- Switches: compact, two per row --------------------------------

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: CortetsuDesign.spacingCompact
            columnSpacing: CortetsuDesign.spacingCompact
            uniformCellWidths: true

            CortetsuActionTile {
                id: microphoneTile
                objectName: "quickMicrophone"
                compact: true
                Layout.fillWidth: true
                label: !root.microphonePresent ? qsTr("Sin micrófono")
                    : CortetsuAudio.sourceMuted ? qsTr("Micrófono silenciado") : qsTr("Micrófono")
                detail: !root.microphonePresent ? qsTr("No hay una entrada de audio")
                    : CortetsuAudio.sourceMuted ? qsTr("Pulsa para reactivarlo")
                    : root.nodeName(CortetsuAudio.source)
                icon: root.microphonePresent && !CortetsuAudio.sourceMuted ? "mic" : "mic_off"
                highlighted: root.microphonePresent && !CortetsuAudio.sourceMuted
                warning: false
                clickable: root.microphonePresent
                onActivated: if (CortetsuAudio.source?.audio)
                    CortetsuAudio.source.audio.muted = !CortetsuAudio.source.audio.muted
            }

            CortetsuActionTile {
                id: dndTile
                objectName: "quickDnd"
                compact: true
                seal: "静"
                Layout.fillWidth: true
                label: qsTr("No molestar")
                detail: CortetsuNotifications.dnd ? qsTr("Avisos en silencio") : qsTr("Apagado")
                icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications"
                highlighted: CortetsuNotifications.dnd
                // DND is an explicit user preference, not a danger state.
                warning: false
                onActivated: CortetsuNotifications.toggleDnd()
            }

            CortetsuActionTile {
                objectName: "quickIdle"
                compact: true
                seal: "醒"
                Layout.fillWidth: true
                label: qsTr("Mantener activo")
                detail: CortetsuIdleInhibitor.enabled ? qsTr("Sin reposo ni bloqueo") : qsTr("Apagado")
                icon: CortetsuIdleInhibitor.enabled ? "coffee" : "bedtime"
                highlighted: CortetsuIdleInhibitor.enabled
                warning: false
                onActivated: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
            }

            CortetsuActionTile {
                objectName: "quickGameMode"
                compact: true
                seal: "遊"
                Layout.fillWidth: true
                label: qsTr("Modo juego")
                detail: GameMode.busy ? qsTr("Un momento…")
                    : GameMode.needsRecovery ? qsTr("Error al aplicar: pulsa para restaurar")
                    : GameMode.status === "UNKNOWN" ? qsTr("Estado desconocido")
                    : GameMode.enabled ? qsTr("Efectos reducidos") : qsTr("Apagado")
                icon: GameMode.enabled ? "sports_esports" : "videogame_asset"
                highlighted: GameMode.enabled
                warning: GameMode.needsRecovery
                onActivated: GameMode.toggle()
            }

            // The colour filter of Ajustes → Pantalla (hyprsunset). With a
            // schedule, a press here holds until the schedule's next turn.
            CortetsuActionTile {
                objectName: "quickNightLight"
                compact: true
                seal: "夜"
                Layout.fillWidth: true
                label: qsTr("Luz nocturna")
                detail: DisplayCalibration.state === "applying" ? qsTr("Aplicando…")
                    : DisplayCalibration.state === "failed" ? qsTr("No se pudo aplicar")
                    : CortetsuConfig.colorCalibrationEnabled ? qsTr("%1 K").arg(CortetsuConfig.colorTemperature)
                    : CortetsuConfig.nightLightSchedule ? qsTr("Desde las %1").arg(CortetsuConfig.nightLightFrom)
                    : qsTr("Apagado")
                icon: CortetsuConfig.colorCalibrationEnabled ? "nightlight" : "light_mode"
                highlighted: CortetsuConfig.colorCalibrationEnabled
                warning: DisplayCalibration.state === "failed"
                clickable: !DisplayCalibration.busy
                onActivated: DisplayCalibration.setEnabled(!CortetsuConfig.colorCalibrationEnabled)
            }

            // An area capture with the existing picker; the panel closes
            // first so it is not in the picture.
            CortetsuActionTile {
                objectName: "quickScreenshot"
                compact: true
                seal: "写"
                Layout.fillWidth: true
                label: qsTr("Captura")
                detail: qsTr("Elegir un área")
                icon: "screenshot_region"
                highlighted: false
                warning: false
                onActivated: root.captureArea()
            }
        }

        // Orbital and the active context share one row of compact tiles,
        // like the toggles below: the panel has to fit a 1080 px screen.
        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuActionTile {
                objectName: "quickOrbital"
                compact: true
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                label: qsTr("Orbital")
                detail: Orbital.activeOn(root.screen.name) ? qsTr("Animado en %1").arg(root.screen.name)
                    : Orbital.output(root.screen.name).state === "error" ? qsTr("Error · fondo estático")
                    : qsTr("Fondos de Steam")
                highlighted: Orbital.activeOn(root.screen.name)
                warning: Orbital.output(root.screen.name).state === "error"
                icon: "animation"
                onActivated: { root.closeQsd(); Orbital.requestSteam(); WallpaperController.open(root.screen); }
            }

            // The active context, if any: pressing ends it and brings back
            // the settings it changed; with none, it opens Ajustes → Contextos.
            CortetsuActionTile {
                objectName: "quickContext"
                compact: true
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                label: CortetsuContexts.active ? CortetsuContexts.active.name : qsTr("Contextos")
                detail: CortetsuContexts.active ? qsTr("Activo · pulsa para salir") : qsTr("Ninguno activo")
                icon: CortetsuContexts.active?.icon ?? "tune"
                highlighted: CortetsuContexts.active !== null
                warning: CortetsuContexts.error.length > 0
                onActivated: CortetsuContexts.active ? CortetsuContexts.deactivate() : root.openSettingsPage("contexts")
            }
        }

        CortetsuDivider { Layout.fillWidth: true; Layout.topMargin: CortetsuDesign.spacingUnit }

        // --- Energy and capture: one line each, with their one control ----

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: !root.laptopBatteryAvailable ? "power"
                    : CortetsuPower.charging ? "battery_charging_full"
                    : CortetsuPower.critical ? "battery_alert" : "battery_full"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuPower.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                objectName: "quickEnergy"
                Layout.fillWidth: true
                text: root.energyLine
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                color: CortetsuPower.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurface
                elide: Text.ElideRight
            }

            CortetsuButton {
                objectName: "quickRecord"
                compact: true
                active: CortetsuRecorder.running
                danger: CortetsuRecorder.running
                icon: CortetsuRecorder.running ? "stop_circle" : "screen_record"
                label: CortetsuRecorder.running ? qsTr("Detener") : qsTr("Grabar")
                tooltipText: CortetsuRecorder.running ? qsTr("Detener la grabación de pantalla")
                    : qsTr("Grabar la pantalla")
                onClicked: CortetsuRecorder.running ? CortetsuRecorder.stop() : CortetsuRecorder.start()
            }
        }

        // The selection is what power-profiles-daemon reports, not what was
        // pressed: a refused change keeps the old tab selected.
        CortetsuTabBar {
            objectName: "quickProfiles"
            Layout.fillWidth: true
            accessibleName: qsTr("Perfil de energía")
            model: root.profiles
            currentIndex: root.profileIndex
            onSelected: index => PowerProfiles.profile = root.profiles[index].profile
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: qsTr("Rendimiento limitado: %1").arg(
                PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorVermillion
            wrapMode: Text.WordWrap
        }
    }
}
