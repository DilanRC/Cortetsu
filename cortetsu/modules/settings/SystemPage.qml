pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../components"
import ".."
import "../../services"
import "../../utils"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property string section
    required property var screen
    required property var screenState

    implicitHeight: content.implicitHeight

    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? -1
    readonly property bool bluetoothEnabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property int bluetoothConnected: (Bluetooth.devices?.values ?? []).filter(device => device.connected).length
    readonly property int batteryPercent: CortetsuPower.percent
    readonly property bool batteryCharging: CortetsuPower.charging
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property string networkName: CortetsuNetwork.active?.ssid
        ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : qsTr("Sin conexión"))
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Conectando")
        : CortetsuNetwork.active
        ? qsTr("Señal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Conexión cableada")
                : qsTr("Sin conexión activa")

    function savePreference(): void {
        CortetsuConfig.save();
    }

    function openRetained(flag: string): void {
        root.screenState.settings = false;
        Qt.callLater(() => {
            if (flag === "wallpaperManager") {
                WallpaperController.open(root.screen);
                return;
            }
            root.screenState.cortetsuState?.closeRetainedOverlaysExcept(flag);
            root.screenState.cortetsuState?.setRetained(flag, true);
        });
    }

    component PreferenceToggle: CortetsuSurface {
        id: preference

        required property string title
        property string detail: ""
        property string icon: "tune"
        property bool checked: false
        property bool controlDisabled: false
        signal changed(bool checked)

        Layout.fillWidth: true
        implicitHeight: 68
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: preference.icon
                iconSize: CortetsuTypography.iconMediumPx
                color: preference.checked ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                CortetsuText {
                    Layout.fillWidth: true
                    text: preference.title
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    visible: preference.detail.length > 0
                    text: preference.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuToggle {
                checked: preference.checked
                disabled: preference.controlDisabled
                onToggled: checked => preference.changed(checked)
            }
        }
    }

    component StatusCard: CortetsuSurface {
        id: status

        required property string title
        required property string value
        property string detail: ""
        property string icon: "info"
        property bool activeState: false
        property bool warningState: false

        Layout.fillWidth: true
        implicitHeight: 78
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: activeState
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42)
            : warningState
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.08)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        outlineColor: activeState
            ? Qt.alpha(CortetsuDesign.colorPrimary, 0.30)
            : warningState
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.36)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: status.icon
                iconSize: CortetsuTypography.iconMediumPx
                color: status.warningState
                    ? CortetsuDesign.colorWarning
                    : status.activeState
                        ? CortetsuDesign.colorPrimary
                        : CortetsuDesign.colorOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                CortetsuText {
                    text: status.title
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: status.value
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                CortetsuText {
                    Layout.fillWidth: true
                    visible: status.detail.length > 0
                    text: status.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }
    }

    component ActionCard: CortetsuSurface {
        id: action

        required property string title
        property string detail: ""
        property string icon: "arrow_forward"
        signal activated()

        Layout.fillWidth: true
        implicitHeight: 64
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.30)
        hoverColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.52)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.28)

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: action.icon
                iconSize: CortetsuTypography.iconMediumPx
                color: CortetsuDesign.colorPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                CortetsuText {
                    Layout.fillWidth: true
                    text: action.title
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    visible: action.detail.length > 0
                    text: action.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
            CortetsuIcon {
                text: "chevron_right"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: action.hovered = true
            onExited: {
                action.hovered = false;
                action.pressed = false;
            }
            onPressedChanged: action.pressed = pressed
            onClicked: action.activated()
        }
    }

    component ShortcutRow: CortetsuSurface {
        id: shortcut

        required property string keys
        required property string action
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: 58
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.66)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.42)

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuSurface {
                Layout.preferredWidth: keyLabel.implicitWidth + CortetsuDesign.spacingStandard * 2
                Layout.preferredHeight: 30
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: Qt.alpha(CortetsuDesign.colorSumi, 0.60)
                outlined: true
                outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.58)
                CortetsuText {
                    id: keyLabel
                    anchors.centerIn: parent
                    text: shortcut.keys
                    textSize: CortetsuTypography.labelSmallPx
                    font.weight: Font.DemiBold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    Layout.fillWidth: true
                    text: shortcut.action
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    visible: shortcut.detail.length > 0
                    text: shortcut.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }
    }

    ColumnLayout {
        id: content
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "desktop"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Comportamiento del escritorio")
                detail: qsTr("Espacios y presentación del escritorio")
            }

            PreferenceToggle {
                title: qsTr("Reloj del escritorio")
                detail: qsTr("Mostrar el reloj de Cortetsu en el escritorio")
                icon: "schedule"
                checked: CortetsuConfig.desktopClockEnabled
                onChanged: checked => {
                    CortetsuConfig.desktopClockEnabled = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Espacios por monitor")
                detail: qsTr("Mantener el estado de espacios separado por pantalla")
                icon: "view_carousel"
                checked: CortetsuConfig.bar.workspaces.perMonitorWorkspaces
                onChanged: checked => {
                    CortetsuConfig.bar.workspaces.perMonitorWorkspaces = checked;
                    root.savePreference();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "bottomhub"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Comportamiento de BottomHub")
                detail: qsTr("Estado e interacción con el puntero")
            }

            PreferenceToggle {
                title: qsTr("Ventanas de estado")
                detail: qsTr("Permitir ventanas contextuales desde los iconos de estado")
                icon: "dock_to_bottom"
                checked: CortetsuConfig.bar.popouts.statusIcons
                onChanged: checked => {
                    CortetsuConfig.bar.popouts.statusIcons = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Desplazamiento del volumen")
                detail: qsTr("Ajustar el volumen con la rueda sobre BottomHub")
                icon: "volume_up"
                checked: CortetsuConfig.bar.scrollActions.volume
                onChanged: checked => {
                    CortetsuConfig.bar.scrollActions.volume = checked;
                    root.savePreference();
                }
            }

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Segmentos visibles")
                detail: qsTr("Elegir qué grupos de BottomHub permanecen en la barra")
            }

            PreferenceToggle {
                title: qsTr("Modo y espacios")
                detail: qsTr("Mostrar controles del lanzador, fondo y espacios")
                icon: "apps"
                checked: CortetsuConfig.bottomHub.segments.mode
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.mode = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Barra de aplicaciones")
                detail: qsTr("Mostrar aplicaciones abiertas y fijadas")
                icon: "apps"
                checked: CortetsuConfig.bottomHub.segments.apps
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.apps = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Bandeja")
                detail: qsTr("Mostrar aplicaciones y menús de StatusNotifier")
                icon: "notifications"
                checked: CortetsuConfig.bottomHub.segments.tray
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.tray = checked;
                    root.savePreference();
                }
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "launcher"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Búsqueda del lanzador")
                detail: qsTr("Ajustar cómo Cortetsu encuentra aplicaciones y acciones")
            }

            PreferenceToggle {
                title: qsTr("Búsqueda aproximada de aplicaciones")
                detail: qsTr("Encontrar nombres de aplicaciones parecidos")
                icon: "search"
                checked: CortetsuConfig.useFuzzyApps
                onChanged: checked => {
                    CortetsuConfig.useFuzzyApps = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Acciones aproximadas")
                detail: qsTr("Usar coincidencias aproximadas para las acciones")
                icon: "bolt"
                checked: CortetsuConfig.useFuzzyActions
                onChanged: checked => {
                    CortetsuConfig.useFuzzyActions = checked;
                    root.savePreference();
                }
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "notifications"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Comportamiento de notificaciones")
                detail: qsTr("Estado de No molestar y preferencias de presentación")
            }

            PreferenceToggle {
                title: qsTr("No molestar")
                detail: CortetsuNotifications.dnd ? qsTr("Las interrupciones están silenciadas") : qsTr("Las notificaciones pueden interrumpir")
                icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
                checked: CortetsuNotifications.dnd
                onChanged: checked => CortetsuNotifications.dnd = checked
            }

            PreferenceToggle {
                title: qsTr("Abrir expandido")
                detail: qsTr("Expandir los grupos al abrir el centro")
                icon: "unfold_more"
                checked: CortetsuConfig.notificationOpenExpanded
                onChanged: checked => {
                    CortetsuConfig.notificationOpenExpanded = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Ocultar en pantalla completa")
                detail: qsTr("Ocultar las notificaciones durante el trabajo a pantalla completa")
                icon: "fullscreen"
                checked: CortetsuConfig.suppressNotificationsInFullscreen
                onChanged: checked => {
                    CortetsuConfig.suppressNotificationsInFullscreen = checked;
                    root.savePreference();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "network"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Estado de la red")
                detail: qsTr("Lectura nativa de NetworkManager; sin controles falsos")
            }

            StatusCard {
                title: qsTr("Conexión actual")
                value: root.networkName
                detail: root.networkDetail
                icon: CortetsuNetwork.activeEthernet
                    ? "cable"
                    : CortetsuNetwork.connecting
                        ? "sync"
                        : CortetsuNetwork.active
                            ? "wifi"
                            : "wifi_off"
                activeState: !!CortetsuNetwork.active || !!CortetsuNetwork.activeEthernet
                warningState: !CortetsuNetwork.active && !CortetsuNetwork.activeEthernet && !CortetsuNetwork.connecting
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Los cambios de conexión se hacen en la ventana de red; esta vista muestra el estado actual.")
                textSize: CortetsuTypography.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "bluetooth"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Bluetooth")
                detail: qsTr("Estado nativo del adaptador")
            }

            StatusCard {
                title: qsTr("Dispositivos")
                value: root.bluetoothEnabled
                    ? root.bluetoothConnected > 0
                        ? qsTr("%1 conectados").arg(root.bluetoothConnected)
                        : qsTr("Listo")
                    : qsTr("Bluetooth apagado")
                detail: root.bluetoothEnabled ? qsTr("Adaptador activado") : qsTr("Adaptador desactivado")
                icon: root.bluetoothConnected > 0 ? "bluetooth_connected" : "bluetooth"
                activeState: root.bluetoothEnabled
            }

            PreferenceToggle {
                title: qsTr("Adaptador Bluetooth")
                detail: qsTr("Activar o desactivar el adaptador predeterminado")
                icon: "bluetooth"
                checked: root.bluetoothEnabled
                controlDisabled: Bluetooth.defaultAdapter === null
                onChanged: checked => {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = checked;
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "audio"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Audio")
                detail: qsTr("Control de salida PipeWire en vivo")
            }

            PreferenceToggle {
                title: CortetsuAudio.muted ? qsTr("Salida silenciada") : qsTr("Salida activada")
                detail: qsTr("Volumen actual %1%").arg(root.volumePercent)
                icon: CortetsuAudio.muted ? "volume_off" : "volume_up"
                checked: !CortetsuAudio.muted
                controlDisabled: !CortetsuAudio.sink?.audio
                onChanged: enabled => {
                    if (CortetsuAudio.sink?.audio)
                        CortetsuAudio.sink.audio.muted = !enabled;
                }
            }

            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 86
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                outlined: true
                outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingCompact
                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: qsTr("Volumen de salida")
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
                        value: CortetsuAudio.volume
                        onMoved: nextValue => CortetsuAudio.setVolume(nextValue)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "power"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Energía")
                detail: qsTr("Lectura de batería y política de reposo")
            }

            StatusCard {
                title: CortetsuPower.laptopBattery ? qsTr("Batería") : qsTr("Fuente de energía")
                value: CortetsuPower.hasBattery ? qsTr("%1%").arg(root.batteryPercent) : qsTr("Alimentación externa")
                detail: CortetsuPower.onBattery ? qsTr("Funcionando con batería") : qsTr("Conectado a alimentación externa")
                icon: CortetsuPower.hasBattery
                    ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging)
                    : "power"
                activeState: !CortetsuPower.onBattery
                warningState: CortetsuPower.critical
            }

            PreferenceToggle {
                title: qsTr("Evitar reposo durante el audio")
                detail: qsTr("Mantener activa la sesión durante la reproducción")
                icon: "music_note"
                checked: CortetsuConfig.idleInhibitWhenAudio
                onChanged: checked => {
                    CortetsuConfig.idleInhibitWhenAudio = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Evitar reposo mientras carga")
                detail: qsTr("Mantener activa la sesión con alimentación externa")
                icon: "power"
                checked: CortetsuConfig.idleInhibitWhenCharging
                onChanged: checked => {
                    CortetsuConfig.idleInhibitWhenCharging = checked;
                    root.savePreference();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "display"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Pantalla")
                detail: qsTr("Brillo y distribución de la pantalla actual")
            }

            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 92
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                outlined: true
                outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingCompact
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
                            text: root.brightnessValue < 0
                                ? qsTr("No disponible")
                                : qsTr("%1%").arg(Math.round(root.brightnessValue * 100))
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
                }
            }

            ActionCard {
                title: qsTr("Abrir gestor de pantallas")
                detail: qsTr("Organizar monitores, modos y opciones de cada pantalla")
                icon: "monitor"
                onActivated: root.openRetained("displayManager")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "input"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Comportamiento de entrada")
                detail: qsTr("Preferencias de interacción del teclado")
            }

            PreferenceToggle {
                title: qsTr("Navegación estilo Vim")
                detail: qsTr("Permitir navegación estilo Vim donde sea compatible")
                icon: "keyboard"
                checked: CortetsuConfig.vimKeybinds
                onChanged: checked => {
                    CortetsuConfig.vimKeybinds = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Aviso de Bloq Mayús")
                detail: qsTr("Mostrar un aviso al cambiar Bloq Mayús")
                icon: "keyboard_capslock"
                checked: CortetsuConfig.toastCapsLockChanged
                onChanged: checked => {
                    CortetsuConfig.toastCapsLockChanged = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Aviso de Bloq Num")
                detail: qsTr("Mostrar un aviso al cambiar Bloq Num")
                icon: "dialpad"
                checked: CortetsuConfig.toastNumLockChanged
                onChanged: checked => {
                    CortetsuConfig.toastNumLockChanged = checked;
                    root.savePreference();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "shortcuts"
            spacing: CortetsuDesign.spacingCompact

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Atajos configurados de Cortetsu")
                detail: qsTr("Vista de solo lectura de los accesos del shell")
            }

            ShortcutRow { keys: qsTr("SUPER + SHIFT + D"); action: qsTr("Panel principal") }
            ShortcutRow { keys: qsTr("SUPER + I"); action: qsTr("Ajustes") }
            ShortcutRow { keys: qsTr("SUPER + /"); action: qsTr("Ajustes rápidos") }
            ShortcutRow { keys: qsTr("SUPER + V"); action: qsTr("Portapapeles") }
            ShortcutRow { keys: qsTr("SUPER + SHIFT + W"); action: qsTr("Gestor de fondos") }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "wallpaper"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Fondo de pantalla")
                detail: qsTr("Fuente actual del fondo de pantalla")
            }

            StatusCard {
                title: qsTr("Fondo de pantalla")
                value: CortetsuWallpapers.applyStatus === "applying"
                    ? qsTr("Aplicando…")
                    : CortetsuWallpapers.applyStatus === "failed"
                        ? qsTr("Error al aplicar")
                        : CortetsuWallpapers.applyStatus === "applied"
                            ? qsTr("Aplicado")
                            : CortetsuWallpapers.actualCurrent.split("/").pop()
                detail: CortetsuWallpapers.applyStatus === "applying" || CortetsuWallpapers.applyStatus === "failed"
                    ? CortetsuWallpapers.applyStatusPath.split("/").pop()
                    : CortetsuWallpapers.actualCurrent
                icon: CortetsuWallpapers.applyStatus === "applying"
                    ? "sync"
                    : CortetsuWallpapers.applyStatus === "failed"
                        ? "error"
                        : "wallpaper"
                activeState: CortetsuConfig.wallpaperEnabled
                    && (CortetsuWallpapers.applyStatus === "applying" || CortetsuWallpapers.applyStatus === "applied")
                warningState: CortetsuWallpapers.applyStatus === "failed"
            }

            PreferenceToggle {
                title: qsTr("Integración del fondo")
                detail: qsTr("Permitir que Cortetsu controle el fondo del escritorio")
                icon: "wallpaper"
                checked: CortetsuConfig.wallpaperEnabled
                onChanged: checked => {
                    CortetsuConfig.wallpaperEnabled = checked;
                    root.savePreference();
                }
            }

            ActionCard {
                title: qsTr("Abrir gestor de fondos")
                detail: qsTr("Explorar el selector orbital y previsualizar un fondo")
                icon: "collections"
                onActivated: root.openRetained("wallpaperManager")
            }
        }
    }
}
