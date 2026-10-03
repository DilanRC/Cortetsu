pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import "../../services"
import "../../theme"
import "sections"

Item {
    id: root

    required property string section
    required property var screen
    required property var screenState

    implicitHeight: content.implicitHeight

    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? -1
    readonly property bool bluetoothEnabled: Connectivity.bluetooth.enabled
    readonly property int bluetoothConnected: Connectivity.bluetooth.connectedCount
    readonly property int batteryPercent: CortetsuPower.percent
    readonly property bool batteryCharging: CortetsuPower.charging
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property int inputVolumePercent: Math.round(CortetsuAudio.sourceVolume * 100)
    readonly property string activeOutputName: CortetsuAudio.sink?.description
        ?? CortetsuAudio.sink?.name ?? qsTr("Sin salida")
    readonly property string activeInputName: CortetsuAudio.source?.description
        ?? CortetsuAudio.source?.name ?? qsTr("Sin entrada")
    readonly property string networkName: CortetsuNetwork.active?.ssid
        ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : qsTr("Sin conexión"))
    readonly property string networkDetail: CortetsuNetwork.connecting
        ? qsTr("Conectando")
        : CortetsuNetwork.active
        ? qsTr("Señal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
            : CortetsuNetwork.activeEthernet
                ? qsTr("Conexión cableada")
                : qsTr("Sin conexión activa")

    readonly property int monitorCount: Hypr.monitors?.values?.length ?? 0
    readonly property int workspaceCount: Hypr.workspaces?.values?.length ?? 0
    readonly property int enabledBottomSegments: [
        CortetsuConfig.bottomHub.segments.mode,
        CortetsuConfig.bottomHub.segments.apps,
        CortetsuConfig.bottomHub.segments.tray,
        CortetsuConfig.bottomHub.segments.status
    ].filter(Boolean).length
    readonly property int enabledStatusSegments: [
        CortetsuConfig.bottomHub.statusCluster.audio,
        CortetsuConfig.bottomHub.statusCluster.network,
        CortetsuConfig.bottomHub.statusCluster.bluetooth,
        CortetsuConfig.bottomHub.statusCluster.battery
    ].filter(Boolean).length
    readonly property int enabledSearchModes: [
        CortetsuConfig.useFuzzyApps,
        CortetsuConfig.useFuzzyActions,
        CortetsuConfig.useFuzzyWallpapers,
        CortetsuConfig.useFuzzySchemes,
        CortetsuConfig.useFuzzyVariants
    ].filter(Boolean).length
    readonly property string batteryStatus: CortetsuPower.hasBattery
        ? qsTr("%1% · %2").arg(batteryPercent).arg(batteryCharging ? qsTr("cargando") : qsTr("batería"))
        : qsTr("Alimentación externa")

    function savePreference(): void {
        CortetsuConfig.save();
    }

    function formatDuration(milliseconds: int): string {
        if (milliseconds <= 0)
            return qsTr("Sin estimación");
        const minutes = Math.round(milliseconds / 60000);
        if (minutes < 60)
            return qsTr("%1 min").arg(minutes);
        return qsTr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60);
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

    ColumnLayout {
        id: content
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        DesktopSection {
            Layout.fillWidth: true
            visible: root.section === "desktop"
            page: root
        }

        BottomHubSection {
            Layout.fillWidth: true
            visible: root.section === "bottomhub"
            page: root
        }

        LauncherSection {
            Layout.fillWidth: true
            visible: root.section === "launcher"
            page: root
        }

        NotificationsSection {
            Layout.fillWidth: true
            visible: root.section === "notifications"
            page: root
        }

        NetworkSection {
            Layout.fillWidth: true
            visible: root.section === "network"
            page: root
        }

        BluetoothSection {
            Layout.fillWidth: true
            visible: root.section === "bluetooth"
            page: root
        }

        AudioSection {
            Layout.fillWidth: true
            visible: root.section === "audio"
            page: root
        }

        PowerSection {
            Layout.fillWidth: true
            visible: root.section === "power"
            page: root
        }

        DisplaySection {
            Layout.fillWidth: true
            visible: root.section === "display"
            page: root
        }

        InputSection {
            Layout.fillWidth: true
            visible: root.section === "input"
            page: root
        }

        ShortcutsSection {
            Layout.fillWidth: true
            visible: root.section === "shortcuts"
            page: root
        }

        WallpaperSection {
            Layout.fillWidth: true
            visible: root.section === "wallpaper"
            page: root
        }
    }
}
