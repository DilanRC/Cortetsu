pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "../modules"

// Optional first-party spectrum boundary. The shell remains usable when cava
// is absent; consumers receive a stable zero-filled list instead of an
// upstream service object.
//
// cava reads the configuration written here, never the user's
// ~/.config/cava/config: the parser below needs raw ASCII output with ';'
// between bars, and cava's default is an ncurses display.
QtObject {
    id: root

    readonly property int barCount: CortetsuConfig.visualiserBars
    property list<real> values: Array(barCount).fill(0)
    property bool available: false
    // Eager singleton construction must never spawn cava while disabled.
    readonly property bool shouldRun: CortetsuConfig.visualiserEnabled
    // The configuration file for the current bar count is on disk.
    property bool configReady: false
    readonly property string configPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/cortetsu-cava.conf`
    readonly property string config: [
        "[general]", `bars = ${barCount}`, "framerate = 30",
        "[input]", "method = pulse",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 100", "bar_delimiter = 59", "frame_delimiter = 10", ""
    ].join("\n")

    function writeConfig(): void {
        root.configReady = false;
        if (root.shouldRun)
            configFile.setText(root.config);
    }

    onShouldRunChanged: {
        if (!shouldRun) {
            root.configReady = false;
            root.available = false;
            root.values = Array(root.barCount).fill(0);
        } else {
            root.writeConfig();
        }
    }
    // A new bar count restarts cava with a matching file.
    onConfigChanged: if (shouldRun) writeConfig()
    Component.onCompleted: if (shouldRun) writeConfig()

    function consume(line: string): void {
        const parsed = line.trim().split(";")
            .map(value => Number(value))
            .filter(value => Number.isFinite(value));
        if (parsed.length === 0)
            return;
        const next = parsed.slice(0, barCount).map(value => Math.max(0, Math.min(1, value / 100)));
        while (next.length < barCount)
            next.push(0);
        values = next;
        available = true;
    }

    property FileView configFile: FileView {
        path: root.configPath
        printErrors: false
        onSaved: root.configReady = true
        onSaveFailed: root.configReady = false
    }

    // startup inventory: cortetsu:spectrum (conditional on cava availability)
    property Process cavaProcess: Process {
        // Without cava the process fails to start once and running turns false.
        command: ["cava", "-p", root.configPath]
        running: root.shouldRun && root.configReady
        onRunningChanged: if (!running) {
            root.available = false;
            root.values = Array(root.barCount).fill(0);
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.consume(data)
        }
    }
}
