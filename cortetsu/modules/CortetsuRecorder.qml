pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property bool running: state.running
    readonly property bool paused: state.paused
    readonly property real elapsed: state.elapsed
    property list<string> startArgs: []

    function loadState(): void {
        try {
            const value = JSON.parse(stateFile.text());
            state.running = Number.isInteger(value.pid) && value.pid > 1;
            state.paused = value.paused === true;
            state.startedAt = value.startedAt || "";
        } catch (error) {
            state.running = false;
            state.paused = false;
            state.startedAt = "";
        }
    }

    function start(extraArgs = []): void {
        startArgs = extraArgs;
        Quickshell.execDetached(["cortetsu-record", "start", ...extraArgs]);
        refreshAfterAction.restart();
    }

    function stop(): void {
        Quickshell.execDetached(["cortetsu-record", "stop"]);
        refreshAfterAction.restart();
    }

    function togglePause(): void {
        Quickshell.execDetached(["cortetsu-record", "pause"]);
        refreshAfterAction.restart();
    }

    QtObject {
        id: state
        property bool running: false
        property bool paused: false
        property real elapsed: 0
        property string startedAt: ""
    }

    Component.onCompleted: loadState()

    FileView {
        id: stateFile
        path: Paths.state + "/record/state.json"
        // The state file is created by the CLI. Watching a missing file makes
        // Quickshell rescan the path continuously; actions reload it explicitly.
        watchChanges: false
        printErrors: false
        onLoaded: root.loadState()
        onFileChanged: root.loadState()
    }

    Timer {
        id: refreshAfterAction
        interval: 300
        repeat: false
        onTriggered: stateFile.reload()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: if (state.startedAt) state.elapsed = Math.max(0, (Date.now() - Date.parse(state.startedAt)) / 1000)
    }
}
