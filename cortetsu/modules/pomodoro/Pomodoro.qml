pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../services"
import "PomodoroModel.js" as Model

// The shell side of Pomodoro, one instance for the whole shell:
// - the state, read from the file cortetsu-pomodoro writes (the helper owns
//   every transition; nothing here recomputes one);
// - the commands of the Calendar card;
// - the daemon that announces phase ends, and the toast for each announcement.
// Before, each Calendar view (two per screen) re-implemented the transitions
// optimistically and Bottom Hub owned the daemon and the toasts.
QtObject {
    id: root

    property var state: ({})
    readonly property string phase: state.phase ?? "IDLE"
    readonly property bool running: Model.isRunning(phase)
    readonly property bool busy: command.running

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu`
    readonly property string helperPath: `${Quickshell.env("HOME")}/.local/bin/cortetsu-pomodoro`

    function parse(text: string): var {
        try {
            const value = JSON.parse(text);
            return value && typeof value === "object" ? value : null;
        } catch (_) {
            return null;
        }
    }

    // start, pause, resume, skip or reset. A click while the previous command
    // runs is dropped: the state it acts on is about to change.
    function run(name: string): void {
        if (command.running)
            return;
        command.command = [helperPath, name];
        command.running = true;
    }

    property FileView stateFile: FileView {
        path: `${root.stateDir}/pomodoro.json`
        watchChanges: true
        printErrors: false
        onLoaded: root.state = root.parse(text()) ?? {}
        onLoadFailed: root.state = ({})
        onFileChanged: reload()
    }

    property Process command: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const next = root.parse(text.trim());
                if (next)
                    root.state = next;
            }
        }
        onExited: root.stateFile.reload()
    }

    // startup inventory: cortetsu:pomodoro
    property Process pomodoroOwner: Process {
        command: [root.helperPath, "daemon"]
        running: true
    }

    // One toast per phase end. Only announcements written after this shell
    // started are shown: an older one was already shown (or missed) by the
    // previous shell and must not repeat on every reload or restart.
    readonly property real startedNs: Date.now() * 1e6
    property FileView announcements: FileView {
        property real consumed: 0

        path: `${root.stateDir}/pomodoro-notification.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const event = root.parse(text());
            const reading = Model.announcement(event, consumed, root.startedNs);
            consumed = reading.sequence;
            if (reading.toast)
                CortetsuToaster.toast(event.title, event.message, "timer");
        }
    }
}
