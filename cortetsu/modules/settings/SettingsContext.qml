pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../services"
import "../launcher/services"
import "../CortetsuOverlayPolicy.js" as OverlayPolicy

// What every Settings page reads: the live state of each domain, one line
// that sums it up for the Nexus, and whether it needs attention. The
// services stay the only source; nothing here is stored or polled.
QtObject {
    id: root

    required property var screen
    required property var screenState

    readonly property var wifi: Connectivity.wifi
    readonly property var bluetooth: Connectivity.bluetooth
    readonly property var policies: ShellState.shellRoot?.policyBridge ?? null

    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? -1
    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)
    readonly property int inputVolumePercent: Math.round(CortetsuAudio.sourceVolume * 100)
    readonly property string outputName: CortetsuAudio.sink?.description ?? CortetsuAudio.sink?.name ?? ""
    readonly property string inputName: CortetsuAudio.source?.description ?? CortetsuAudio.source?.name ?? ""
    readonly property int monitorCount: Hypr.monitors?.values?.length ?? 0
    readonly property string wallpaperName: CortetsuWallpapers.actualCurrent.split("/").pop()
    readonly property string keyboardLayout: Hypr.keyboardKnown ? (Hypr.kbLayoutFull || Hypr.kbLayout) : ""

    // The generation that is running, as its builder recorded it. A source
    // checkout has no such file and says so.
    property var build: ({})
    readonly property string revision: String(build.repositoryRevision ?? "").slice(0, 7)
    readonly property FileView buildFile: FileView {
        path: `${Quickshell.shellDir}/BUILD.json`
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.build = data && typeof data === "object" ? data : ({});
            } catch (_) {
                root.build = ({});
            }
        }
    }

    // One line per page for the Nexus, keyed by category id.
    readonly property QtObject summary: QtObject {
        readonly property string network: !root.wifi.wifiEnabled && !root.wifi.activeEthernet
            ? qsTr("Wi-Fi apagado")
            : root.wifi.activeNetwork
                ? root.wifi.activeNetwork.name
                : root.wifi.activeEthernet
                    ? qsTr("Cable")
                    : root.wifi.connecting ? qsTr("Conectando") : qsTr("Sin conexión")
        readonly property string bluetooth: !root.bluetooth.adapter
            ? qsTr("Sin adaptador")
            : !root.bluetooth.enabled
                ? qsTr("Apagado")
                : root.bluetooth.connectedCount === 1
                    ? qsTr("1 conectado")
                    : root.bluetooth.connectedCount > 1
                        ? qsTr("%1 conectados").arg(root.bluetooth.connectedCount)
                        : qsTr("Encendido")
        readonly property string audio: !CortetsuAudio.sink
            ? qsTr("Sin salida")
            : CortetsuAudio.muted ? qsTr("Silenciado") : qsTr("%1 %").arg(root.volumePercent)
        readonly property string display: root.brightnessValue >= 0
            ? qsTr("%1 %").arg(Math.round(root.brightnessValue * 100))
            : root.monitorCount === 1 ? qsTr("1 pantalla") : qsTr("%1 pantallas").arg(root.monitorCount)
        readonly property string power: !CortetsuPower.hasBattery
            ? qsTr("Corriente")
            : CortetsuPower.charging
                ? qsTr("%1 % · cargando").arg(CortetsuPower.percent)
                : qsTr("%1 %").arg(CortetsuPower.percent)
        readonly property string notifications: CortetsuNotifications.dnd
            ? qsTr("No molestar")
            : CortetsuNotifications.count === 1
                ? qsTr("1 guardada")
                : CortetsuNotifications.count > 1 ? qsTr("%1 guardadas").arg(CortetsuNotifications.count) : ""
        readonly property string input: root.keyboardLayout
        readonly property string appearance: Schemes.currentScheme
        readonly property string wallpaper: root.wallpaperName
        readonly property string desktop: CortetsuConfig.dashboard.enabled ? "" : qsTr("Sin Dashboard")
        readonly property string bottomhub: ""
        readonly property string launcher: CortetsuConfig.launcher.enabled ? "" : qsTr("Apagado")
        readonly property string shortcuts: ""
        readonly property string automation: root.policies?.statusText || qsTr("No disponible")
        readonly property string about: root.revision
    }

    // Why a page needs a look, or "" when it does not. Only failures and
    // states the user must act on: an ordinary "off" is not an alert.
    readonly property QtObject alert: QtObject {
        readonly property string network: root.wifi.operation.state === "failed"
            ? root.wifi.operation.lastError
            : root.wifi.wifiEnabled && !root.wifi.activeNetwork && !root.wifi.activeEthernet && !root.wifi.connecting
                ? qsTr("Sin conexión")
                : ""
        readonly property string bluetooth: root.bluetooth.operation.state === "failed"
            ? root.bluetooth.operation.lastError
            : ""
        readonly property string audio: CortetsuAudio.sink ? "" : qsTr("No hay dispositivo de salida")
        readonly property string display: ""
        readonly property string power: CortetsuPower.critical ? qsTr("Batería baja") : ""
        readonly property string notifications: ""
        readonly property string input: ""
        readonly property string appearance: Schemes.applyStatus === "failed" ? Schemes.applyError : ""
        readonly property string wallpaper: CortetsuWallpapers.applyStatus === "failed"
            ? (CortetsuWallpapers.applyError || qsTr("No se pudo aplicar el fondo"))
            : ""
        readonly property string desktop: ""
        readonly property string bottomhub: ""
        readonly property string launcher: ""
        readonly property string shortcuts: ""
        readonly property string automation: root.policies?.lastError || ""
        readonly property string about: ""
    }

    function formatDuration(seconds: int): string {
        if (seconds <= 0)
            return qsTr("Sin estimación");
        const minutes = Math.round(seconds / 60);
        if (minutes < 60)
            return qsTr("%1 min").arg(minutes);
        return qsTr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60);
    }

    // Leaves Settings and opens another surface on the same screen, with the
    // same exclusivity as its shortcut (CortetsuOverlayPolicy.open).
    function openSurface(flag: string): void {
        root.screenState.settings = false;
        Qt.callLater(() => OverlayPolicy.open(CortetsuShellState.allStates(), root.screenState, flag));
    }
}
