pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
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
    readonly property int batteryPercent: Math.round((UPower.displayDevice?.percentage ?? 0) * 100)
    readonly property bool batteryCharging: [
        UPowerDeviceState.Charging,
        UPowerDeviceState.FullyCharged,
        UPowerDeviceState.PendingCharge
    ].includes(UPower.displayDevice?.state)
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property string networkName: CortetsuNetwork.active?.ssid
        ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : qsTr("Offline"))
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Connecting")
        : CortetsuNetwork.active
            ? qsTr("Signal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Wired connection")
                : qsTr("No active connection")

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
                title: qsTr("Desktop behavior")
                detail: qsTr("First-party workspace and desktop presentation")
            }

            PreferenceToggle {
                title: qsTr("Desktop clock")
                detail: qsTr("Show the Cortetsu clock directly on the desktop")
                icon: "schedule"
                checked: CortetsuConfig.desktopClockEnabled
                onChanged: checked => {
                    CortetsuConfig.desktopClockEnabled = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Per-monitor workspaces")
                detail: qsTr("Keep BottomHub workspace state scoped to each display")
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
                title: qsTr("BottomHub behavior")
                detail: qsTr("Status context and pointer interactions")
            }

            PreferenceToggle {
                title: qsTr("Status popouts")
                detail: qsTr("Allow contextual system popouts from status icons")
                icon: "dock_to_bottom"
                checked: CortetsuConfig.bar.popouts.statusIcons
                onChanged: checked => {
                    CortetsuConfig.bar.popouts.statusIcons = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Volume scroll")
                detail: qsTr("Adjust volume by scrolling the BottomHub control")
                icon: "volume_up"
                checked: CortetsuConfig.bar.scrollActions.volume
                onChanged: checked => {
                    CortetsuConfig.bar.scrollActions.volume = checked;
                    root.savePreference();
                }
            }

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Visible segments")
                detail: qsTr("Choose which BottomHub islands stay in the dock")
            }

            PreferenceToggle {
                title: qsTr("Mode and workspaces")
                detail: qsTr("Show launcher, wallpaper and workspace controls")
                icon: "apps"
                checked: CortetsuConfig.bottomHub.segments.mode
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.mode = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("App rail")
                detail: qsTr("Show running and pinned applications")
                icon: "apps"
                checked: CortetsuConfig.bottomHub.segments.apps
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.apps = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Tray")
                detail: qsTr("Show StatusNotifier applications and menus")
                icon: "notifications"
                checked: CortetsuConfig.bottomHub.segments.tray
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.tray = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Status cluster")
                detail: qsTr("Show notifications, hardware and session controls")
                icon: "tune"
                checked: CortetsuConfig.bottomHub.segments.status
                onChanged: checked => {
                    CortetsuConfig.bottomHub.segments.status = checked;
                    root.savePreference();
                }
            }

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Visible status controls")
                detail: qsTr("Choose which hardware controls stay in the BottomHub")
            }

            PreferenceToggle {
                title: qsTr("Volume")
                detail: qsTr("Show the audio control and its contextual popup")
                icon: "volume_up"
                checked: CortetsuConfig.bottomHub.statusCluster.audio
                onChanged: checked => {
                    CortetsuConfig.bottomHub.statusCluster.audio = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Network")
                detail: qsTr("Show Wi-Fi and Ethernet state")
                icon: "wifi"
                checked: CortetsuConfig.bottomHub.statusCluster.network
                onChanged: checked => {
                    CortetsuConfig.bottomHub.statusCluster.network = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Bluetooth")
                detail: qsTr("Show the Bluetooth adapter and device state")
                icon: "bluetooth"
                checked: CortetsuConfig.bottomHub.statusCluster.bluetooth
                onChanged: checked => {
                    CortetsuConfig.bottomHub.statusCluster.bluetooth = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Battery")
                detail: qsTr("Show battery and power state")
                icon: "battery_full"
                checked: CortetsuConfig.bottomHub.statusCluster.battery
                onChanged: checked => {
                    CortetsuConfig.bottomHub.statusCluster.battery = checked;
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
                title: qsTr("Launcher search")
                detail: qsTr("Tune how Cortetsu finds applications and actions")
            }

            PreferenceToggle {
                title: qsTr("Fuzzy application search")
                detail: qsTr("Match approximate application names")
                icon: "search"
                checked: CortetsuConfig.useFuzzyApps
                onChanged: checked => {
                    CortetsuConfig.useFuzzyApps = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Fuzzy actions")
                detail: qsTr("Use approximate matching for launcher actions")
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
                title: qsTr("Notification behavior")
                detail: qsTr("Live DND state and presentation preferences")
            }

            PreferenceToggle {
                title: qsTr("Do Not Disturb")
                detail: CortetsuNotifications.dnd ? qsTr("Notification interruptions are silenced") : qsTr("Notifications may interrupt")
                icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
                checked: CortetsuNotifications.dnd
                onChanged: checked => CortetsuNotifications.dnd = checked
            }

            PreferenceToggle {
                title: qsTr("Open expanded")
                detail: qsTr("Expand notification groups when the center opens")
                icon: "unfold_more"
                checked: CortetsuConfig.notificationOpenExpanded
                onChanged: checked => {
                    CortetsuConfig.notificationOpenExpanded = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Suppress in fullscreen")
                detail: qsTr("Keep notification surfaces out of fullscreen work")
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
                title: qsTr("Network status")
                detail: qsTr("Native NetworkManager readback; no fake controls")
            }

            StatusCard {
                title: qsTr("Current connection")
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
                text: qsTr("Connection changes stay in the native network popout until the service exposes a safe first-party write contract here.")
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
                detail: qsTr("Native adapter state")
            }

            StatusCard {
                title: qsTr("Devices")
                value: root.bluetoothEnabled
                    ? root.bluetoothConnected > 0
                        ? qsTr("%1 connected").arg(root.bluetoothConnected)
                        : qsTr("Ready")
                    : qsTr("Bluetooth off")
                detail: root.bluetoothEnabled ? qsTr("Adapter enabled") : qsTr("Adapter disabled")
                icon: root.bluetoothConnected > 0 ? "bluetooth_connected" : "bluetooth"
                activeState: root.bluetoothEnabled
            }

            PreferenceToggle {
                title: qsTr("Bluetooth adapter")
                detail: qsTr("Turn the default adapter on or off")
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
                detail: qsTr("Live PipeWire output control")
            }

            PreferenceToggle {
                title: CortetsuAudio.muted ? qsTr("Output muted") : qsTr("Output enabled")
                detail: qsTr("Current volume %1%").arg(root.volumePercent)
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
                            text: qsTr("Output volume")
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
                title: qsTr("Power")
                detail: qsTr("Battery readback and idle policy")
            }

            StatusCard {
                title: UPower.displayDevice?.isLaptopBattery ? qsTr("Battery") : qsTr("Power source")
                value: UPower.displayDevice?.isLaptopBattery ? qsTr("%1%").arg(root.batteryPercent) : qsTr("External power")
                detail: UPower.onBattery ? qsTr("Running on battery") : qsTr("Connected to external power")
                icon: UPower.displayDevice?.isLaptopBattery
                    ? Icons.getBatteryIcon(UPower.displayDevice?.percentage ?? 0, root.batteryCharging)
                    : "power"
                activeState: !UPower.onBattery
                warningState: UPower.onBattery && root.batteryPercent <= 20
            }

            PreferenceToggle {
                title: qsTr("Prevent idle while audio plays")
                detail: qsTr("Keep the session active during playback")
                icon: "music_note"
                checked: CortetsuConfig.idleInhibitWhenAudio
                onChanged: checked => {
                    CortetsuConfig.idleInhibitWhenAudio = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Prevent idle while charging")
                detail: qsTr("Keep the session active on external power")
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
                title: qsTr("Display")
                detail: qsTr("Current-screen brightness and display layout")
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
                            text: qsTr("Brightness")
                            textSize: CortetsuTypography.bodyPx
                            font.weight: Font.DemiBold
                        }
                        CortetsuText {
                            text: root.brightnessValue < 0
                                ? qsTr("Unavailable")
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
                title: qsTr("Open Display Manager")
                detail: qsTr("Arrange monitors, modes and display-specific options")
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
                title: qsTr("Input behavior")
                detail: qsTr("Shell keyboard interaction preferences")
            }

            PreferenceToggle {
                title: qsTr("Vim-style navigation")
                detail: qsTr("Allow shell surfaces to expose Vim-oriented navigation where supported")
                icon: "keyboard"
                checked: CortetsuConfig.vimKeybinds
                onChanged: checked => {
                    CortetsuConfig.vimKeybinds = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Caps Lock feedback")
                detail: qsTr("Show semantic feedback when Caps Lock changes")
                icon: "keyboard_capslock"
                checked: CortetsuConfig.toastCapsLockChanged
                onChanged: checked => {
                    CortetsuConfig.toastCapsLockChanged = checked;
                    root.savePreference();
                }
            }

            PreferenceToggle {
                title: qsTr("Num Lock feedback")
                detail: qsTr("Show semantic feedback when Num Lock changes")
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
                title: qsTr("Configured Cortetsu bindings")
                detail: qsTr("Read-only view of the first-party shell entry points")
            }

            ShortcutRow { keys: qsTr("SUPER + SHIFT + D"); action: qsTr("Dashboard") }
            ShortcutRow { keys: qsTr("SUPER + I"); action: qsTr("Settings") }
            ShortcutRow { keys: qsTr("SUPER + /"); action: qsTr("Quick Settings") }
            ShortcutRow { keys: qsTr("SUPER + V"); action: qsTr("Clipboard") }
            ShortcutRow { keys: qsTr("SUPER + SHIFT + W"); action: qsTr("Wallpaper Manager") }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.section === "wallpaper"
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Wallpaper")
                detail: qsTr("Current first-party wallpaper source")
            }

            StatusCard {
                title: qsTr("Wallpaper")
                value: CortetsuWallpapers.applyStatus === "applying"
                    ? qsTr("Applying…")
                    : CortetsuWallpapers.applyStatus === "failed"
                        ? qsTr("Apply failed")
                        : CortetsuWallpapers.applyStatus === "applied"
                            ? qsTr("Applied")
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
                title: qsTr("Wallpaper integration")
                detail: qsTr("Allow Cortetsu to own the desktop wallpaper surface")
                icon: "wallpaper"
                checked: CortetsuConfig.wallpaperEnabled
                onChanged: checked => {
                    CortetsuConfig.wallpaperEnabled = checked;
                    root.savePreference();
                }
            }

            ActionCard {
                title: qsTr("Open Wallpaper Manager")
                detail: qsTr("Browse the orbital selector and preview a wallpaper")
                icon: "collections"
                onActivated: root.openRetained("wallpaperManager")
            }
        }
    }
}
