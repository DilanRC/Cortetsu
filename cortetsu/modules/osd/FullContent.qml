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
// a card with its frequent operation in reach and a chevron to its page in
// Ajustes. Audio and brightness come first because they are touched most;
// connections, energy and what is playing follow; the switches close the
// panel as a row of icon-over-label actions.
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

    // The track position only moves while someone is looking at it.
    Timer {
        running: !!root.player && root.player.isPlaying && (root.screenState?.osd ?? false)
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    function clock(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    function nodeName(node): string {
        return node?.description || node?.nickname || node?.name || qsTr("Dispositivo sin nombre");
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: CortetsuDesign.spacingCompact + 2

        // Identity once, small and still: the mark is the product's
        // signature here, not a reaction to the pointer.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            spacing: CortetsuDesign.spacingStandard

            CortetsuEvolvingMark {
                phase: "Ascended"
                animated: false
                monochrome: true
                monochromeColor: CortetsuDesign.colorPrimary
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Ajustes rápidos")
                    textSize: CortetsuTypography.titleSmallPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("CORTETSU · CONTROL DEL SISTEMA")
                    textSize: CortetsuTypography.labelSmallPx
                    font.letterSpacing: 1.4
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
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

        // --- Audio: the output, its level and, on demand, every device ----

        QuickCard {
            objectName: "quickAudio"
            Layout.fillWidth: true
            icon: "graphic_eq"
            title: qsTr("Audio")
            detail: root.volumeAvailable ? qsTr("Salida: %1").arg(root.nodeName(CortetsuAudio.sink)) : qsTr("Sin salida de audio")
            actionTooltip: qsTr("Sonido en Ajustes: dispositivos, aplicaciones, ecualizador y límites")
            onActionRequested: root.openSettingsPage("sound")

            // The level in one line: mute, the slider, the read-back amount
            // and the device list.
            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuButton {
                    id: muteButton
                    compact: true
                    disabled: !root.volumeAvailable
                    active: CortetsuAudio.muted
                    icon: CortetsuAudio.muted || !root.volumeAvailable ? "volume_off" : "volume_up"
                    label: ""
                    tooltipText: CortetsuAudio.muted ? qsTr("Activar el sonido") : qsTr("Silenciar")
                    onClicked: if (CortetsuAudio.sink?.audio)
                        CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted
                }
                CortetsuSlider {
                    Layout.fillWidth: true
                    accessibleName: qsTr("Volumen")
                    value: CortetsuAudio.volume
                    // As in Ajustes → Sonido: the limit, or the current level
                    // if something outside Cortetsu set it higher.
                    to: Math.max(CortetsuConfig.maxVolume, CortetsuAudio.volume)
                    disabled: !root.volumeAvailable
                    onMoved: nextValue => CortetsuAudio.setVolume(nextValue)
                }
                CortetsuText {
                    Layout.minimumWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: !root.volumeAvailable ? qsTr("No disponible")
                        : CortetsuAudio.muted ? qsTr("Silenciado") : `${root.volumePercent}%`
                    textSize: CortetsuTypography.labelMediumPx
                    color: CortetsuAudio.muted || !root.volumeAvailable ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorOnSurface
                }
                CortetsuButton {
                    id: expandButton
                    visible: CortetsuAudio.sinks.length + CortetsuAudio.sources.length > 1 || CortetsuAudio.streams.length > 0
                    compact: true
                    active: root.audioExpanded
                    icon: root.audioExpanded ? "expand_less" : "expand_more"
                    label: ""
                    tooltipText: root.audioExpanded ? qsTr("Ocultar dispositivos") : qsTr("Elegir dispositivo")
                    onClicked: root.audioExpanded = !root.audioExpanded
                }
            }

            // Output and input devices and app volumes, on demand. A row is
            // the device; the selected one is the default PipeWire reports.
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

            CortetsuDivider { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuIcon {
                    Layout.preferredWidth: muteButton.implicitWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: "light_mode"
                    iconSize: CortetsuTypography.iconSmallPx
                    color: root.brightnessValue >= 0 ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
                }
                CortetsuSlider {
                    Layout.fillWidth: true
                    visible: root.brightnessValue >= 0
                    accessibleName: qsTr("Brillo")
                    value: Math.max(0, root.brightnessValue)
                    onMoved: nextValue => root.brightnessMonitor?.setBrightness(nextValue)
                }
                CortetsuText {
                    Layout.fillWidth: root.brightnessValue < 0
                    Layout.minimumWidth: 40
                    horizontalAlignment: root.brightnessValue < 0 ? Text.AlignLeft : Text.AlignRight
                    text: root.brightnessValue < 0 ? qsTr("Brillo: esta pantalla no lo permite")
                        : `${Math.round(root.brightnessValue * 100)}%`
                    textSize: CortetsuTypography.labelMediumPx
                    color: root.brightnessValue < 0 ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorOnSurface
                }
                // Keeps the slider as long as the volume one above.
                Item {
                    visible: root.brightnessValue >= 0 && expandButton.visible
                    Layout.preferredWidth: expandButton.implicitWidth
                }
            }
        }

        // --- Connections: the Wi-Fi link leads, the radios follow ---------

        QuickCard {
            Layout.fillWidth: true
            icon: "lan"
            title: qsTr("Red y conexiones")
            actionTooltip: qsTr("Red en Ajustes")
            onActionRequested: root.openSettingsPage("network")

            // The radio is the action; the link it holds is the detail. A
            // machine without a Wi-Fi device, or with it blocked by its
            // switch, gets the same tile as a reading with nothing to press.
            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuActionTile {
                    id: networkTile
                    objectName: "quickWifi"
                    focus: true
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    compact: true
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
                    compact: true
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
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
        }

        // --- Energy: the battery line and the profile it runs on ----------

        QuickCard {
            Layout.fillWidth: true
            attention: CortetsuPower.critical

            // The battery line and the profile it runs on, in one row.
            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuIcon {
                    text: !root.laptopBatteryAvailable ? "power"
                        : CortetsuPower.charging ? "battery_charging_full"
                        : CortetsuPower.critical ? "battery_alert" : "battery_full"
                    iconSize: CortetsuTypography.iconSmallPx
                    color: CortetsuPower.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                }
                ColumnLayout {
                    Layout.preferredWidth: 112
                    Layout.maximumWidth: 112
                    spacing: 0
                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("Energía")
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        objectName: "quickEnergy"
                        Layout.fillWidth: true
                        text: root.energyLine
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuPower.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
                // The selection is what power-profiles-daemon reports, not
                // what was pressed: a refused change keeps the old tab.
                CortetsuTabBar {
                    objectName: "quickProfiles"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 260
                    accessibleName: qsTr("Perfil de energía")
                    model: root.profiles
                    currentIndex: root.profileIndex
                    onSelected: index => PowerProfiles.profile = root.profiles[index].profile
                }
                CortetsuButton {
                    compact: true
                    icon: "chevron_right"
                    label: ""
                    tooltipText: qsTr("Energía en Ajustes")
                    onClicked: root.openSettingsPage("power")
                }
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

        // --- Now playing: only while a player exists -----------------------

        QuickCard {
            objectName: "quickMedia"
            Layout.fillWidth: true
            visible: !!root.player
            icon: root.player?.isPlaying ? "graphic_eq" : "play_circle"
            title: qsTr("Medios")
            detail: root.player ? Players.getIdentity(root.player) : ""

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingStandard

                Item {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    Rectangle {
                        anchors.fill: parent
                        radius: CortetsuDesign.radiusSmall
                        color: Qt.alpha(CortetsuDesign.colorIndicator, 0.18)
                        visible: cover.status !== Image.Ready
                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: "music_note"
                            iconSize: CortetsuTypography.iconMediumPx
                            color: CortetsuDesign.colorPrimary
                        }
                    }
                    CortetsuRoundedImage {
                        id: cover
                        anchors.fill: parent
                        radius: CortetsuDesign.radiusSmall
                        source: Players.getArtUrl(root.player)
                        visible: status === Image.Ready
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.player?.trackTitle || qsTr("Sin título")
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.player?.trackArtist ?? ""
                        visible: text.length > 0
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
                    active: true
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

            // Where the track is; dragging seeks when the player allows it.
            RowLayout {
                Layout.fillWidth: true
                visible: (root.player?.lengthSupported ?? false) && (root.player?.length ?? 0) > 0
                spacing: CortetsuDesign.spacingCompact
                CortetsuText {
                    text: root.clock(root.player?.position ?? 0)
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                CortetsuSlider {
                    Layout.fillWidth: true
                    accessibleName: qsTr("Posición de la pista")
                    accessibleValue: root.clock(root.player?.position ?? 0)
                    value: root.player?.position ?? 0
                    to: Math.max(1, root.player?.length ?? 1)
                    step: 5
                    disabled: !(root.player?.canSeek ?? false)
                    onMoved: nextValue => { if (root.player) root.player.position = nextValue; }
                }
                CortetsuText {
                    text: root.clock(root.player?.length ?? 0)
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }
        }

        // --- Actions: icon over label, three to a row ----------------------

        GridLayout {
            objectName: "quickActions"
            Layout.fillWidth: true
            Layout.topMargin: 2
            columns: 3
            rowSpacing: CortetsuDesign.spacingCompact
            columnSpacing: CortetsuDesign.spacingCompact
            uniformCellWidths: true

            CortetsuActionTile {
                id: dndTile
                objectName: "quickDnd"
                stacked: true
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
                id: microphoneTile
                objectName: "quickMicrophone"
                stacked: true
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
                objectName: "quickGameMode"
                stacked: true
                seal: "遊"
                Layout.fillWidth: true
                label: qsTr("Modo juego")
                detail: GameMode.busy ? qsTr("Un momento…")
                    : GameMode.needsRecovery ? qsTr("Error: pulsa para restaurar")
                    : GameMode.status === "UNKNOWN" ? qsTr("Estado desconocido")
                    : GameMode.enabled ? qsTr("Efectos reducidos") : qsTr("Apagado")
                icon: GameMode.enabled ? "sports_esports" : "videogame_asset"
                highlighted: GameMode.enabled
                warning: GameMode.needsRecovery
                onActivated: GameMode.toggle()
            }

            CortetsuActionTile {
                objectName: "quickIdle"
                stacked: true
                seal: "醒"
                Layout.fillWidth: true
                label: qsTr("Mantener activo")
                detail: CortetsuIdleInhibitor.enabled ? qsTr("Sin reposo ni bloqueo") : qsTr("Apagado")
                icon: CortetsuIdleInhibitor.enabled ? "coffee" : "bedtime"
                highlighted: CortetsuIdleInhibitor.enabled
                warning: false
                onActivated: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
            }

            // The colour filter of Ajustes → Pantalla (hyprsunset). With a
            // schedule, a press here holds until the schedule's next turn.
            CortetsuActionTile {
                objectName: "quickNightLight"
                stacked: true
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
                stacked: true
                Layout.fillWidth: true
                label: qsTr("Captura")
                detail: qsTr("Elegir un área")
                icon: "screenshot_region"
                highlighted: false
                warning: false
                onActivated: root.captureArea()
            }

            CortetsuActionTile {
                objectName: "quickRecord"
                stacked: true
                Layout.fillWidth: true
                label: CortetsuRecorder.running ? qsTr("Detener grabación") : qsTr("Grabar pantalla")
                detail: CortetsuRecorder.running ? qsTr("Grabando") : qsTr("Toda la pantalla")
                icon: CortetsuRecorder.running ? "stop_circle" : "screen_record"
                highlighted: CortetsuRecorder.running
                warning: false
                onActivated: CortetsuRecorder.running ? CortetsuRecorder.stop() : CortetsuRecorder.start()
            }

            CortetsuActionTile {
                objectName: "quickOrbital"
                stacked: true
                Layout.fillWidth: true
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
                stacked: true
                Layout.fillWidth: true
                label: CortetsuContexts.active ? qsTr("Salir de %1").arg(CortetsuContexts.active.name) : qsTr("Contextos")
                detail: CortetsuContexts.active ? qsTr("Activo · pulsa para salir") : qsTr("Ninguno activo")
                icon: CortetsuContexts.active?.icon ?? "tune"
                highlighted: CortetsuContexts.active !== null
                warning: CortetsuContexts.error.length > 0
                onActivated: CortetsuContexts.active ? CortetsuContexts.deactivate() : root.openSettingsPage("contexts")
            }
        }
    }
}
