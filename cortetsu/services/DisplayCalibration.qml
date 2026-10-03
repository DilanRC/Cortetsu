pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"

// Colour filter of the display (hyprsunset). It lives with the shell, not
// with a Settings page: a saved filter is restored at start whether or not
// Settings is ever opened. The preferences hold what was asked for; `state`
// and `error` say whether the display followed.
Singleton {
    id: root

    // idle | applying | applied | failed
    property string state: "idle"
    property string error: ""
    property bool requestedEnabled: false
    readonly property bool busy: service.running || temperatureProcess.running || gammaProcess.running

    function setEnabled(enabled: bool): void {
        CortetsuConfig.colorCalibrationEnabled = enabled;
        root.change();
    }

    function setTemperature(kelvin: real): void {
        CortetsuConfig.colorTemperature = Math.max(2500, Math.min(6500, Math.round(kelvin / 100) * 100));
        root.change();
    }

    function setGamma(percent: real): void {
        CortetsuConfig.colorGamma = Math.max(50, Math.min(150, Math.round(percent)));
        root.change();
    }

    // A change made by the user is stored and applied; restoring at start
    // only applies what is already stored.
    function change(): void {
        CortetsuConfig.save();
        root.apply();
    }

    // Runs once the previous change has finished, so a dragged slider ends
    // on its last value without queueing a process per step.
    function apply(): void {
        if (root.busy) {
            retry.restart();
            return;
        }
        root.error = "";
        root.state = "applying";
        root.requestedEnabled = CortetsuConfig.colorCalibrationEnabled;
        service.command = ["systemctl", "--user", root.requestedEnabled ? "start" : "stop", "hyprsunset.service"];
        service.running = true;
    }

    function fail(message: string): void {
        root.error = message;
        root.state = "failed";
    }

    function restore(): void {
        if (CortetsuConfig.loaded && CortetsuConfig.colorCalibrationEnabled)
            root.apply();
    }

    Component.onCompleted: root.restore()

    Connections {
        target: CortetsuConfig
        function onLoadedChanged(): void { root.restore(); }
    }

    // startup inventory: cortetsu:display-calibration-control
    Process {
        id: service
        command: []
        stderr: StdioCollector { id: serviceError }
        onExited: code => {
            if (code !== 0) {
                // The switch goes back to what the display is really doing.
                CortetsuConfig.colorCalibrationEnabled = !root.requestedEnabled;
                CortetsuConfig.save();
                root.fail(serviceError.text.trim() || qsTr("No se pudo cambiar el filtro de color"));
                return;
            }
            if (CortetsuConfig.colorCalibrationEnabled)
                temperatureProcess.running = true;
            else
                root.state = "applied";
        }
    }

    Process {
        id: temperatureProcess
        command: ["hyprctl", "hyprsunset", "temperature", String(CortetsuConfig.colorTemperature)]
        stderr: StdioCollector { id: temperatureError }
        onExited: code => {
            if (code !== 0) {
                root.fail(temperatureError.text.trim() || qsTr("No se pudo aplicar la temperatura"));
                return;
            }
            gammaProcess.running = true;
        }
    }

    Process {
        id: gammaProcess
        command: ["hyprctl", "hyprsunset", "gamma", String(CortetsuConfig.colorGamma)]
        stderr: StdioCollector { id: gammaError }
        onExited: code => {
            if (code !== 0)
                root.fail(gammaError.text.trim() || qsTr("No se pudo aplicar la gamma"));
            else
                root.state = "applied";
        }
    }

    Timer { id: retry; interval: 180; onTriggered: root.apply() }
}
