pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Writes a value per key through a helper process, one at a time. A slider
// drag outruns the helper, so only the latest value of each key waits; a
// value equal to the one being written is not written again. The owner
// shows what was asked for and reacts to the answer.
QtObject {
    id: root

    // (key, value) => argv of the helper that writes it.
    required property var command
    // Shown when the helper cannot even start.
    required property string startError

    // A write is running. With `waiting` empty too, nothing is outstanding.
    readonly property bool busy: process.running || settling
    readonly property bool idle: !busy && Object.keys(waiting).length === 0

    // The helper answered: `result` is its JSON, or null if it printed none.
    signal answered(string key, var value, var result)
    // The helper could not be started; nothing was written.
    signal unstartable(string key, var value, string error)
    // The last outstanding write finished.
    signal drained()

    property var waiting: ({})
    property string sentKey: ""
    property var sentValue: undefined
    // Between the helper stopping and the next write (or drained).
    property bool settling: false

    function enqueue(key: string, value: var): void {
        const next = Object.assign({}, waiting);
        if (busy && key === sentKey && value === sentValue)
            delete next[key];
        else
            next[key] = value;
        waiting = next;
        advance();
    }

    function isWaiting(key: string): bool {
        return waiting[key] !== undefined;
    }

    function advance(): void {
        if (process.running)
            return;
        const key = Object.keys(waiting)[0];
        if (key === undefined) {
            if (settling) {
                settling = false;
                drained();
            }
            return;
        }
        const rest = Object.assign({}, waiting);
        sentKey = key;
        sentValue = rest[key];
        delete rest[key];
        waiting = rest;
        settling = true;
        process.answer = undefined;
        process.exitSeen = false;
        process.command = root.command(sentKey, sentValue);
        process.running = true;
    }

    function finish(): void {
        if (process.answer !== undefined)
            answered(sentKey, sentValue, process.answer);
        else
            unstartable(sentKey, sentValue, startError);
        advance();
    }

    readonly property Process process: Process {
        property var answer: undefined
        property bool exitSeen: false
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {}
                root.process.answer = parsed;
                if (root.process.exitSeen)
                    root.finish();
            }
        }
        // The output and the exit arrive in either order: finish on the
        // second. A helper that cannot start emits neither.
        onExited: {
            exitSeen = true;
            if (answer !== undefined)
                root.finish();
        }
        onRunningChanged: if (!running) Qt.callLater(root.neverRan)
    }

    function neverRan(): void {
        if (!settling || process.running || process.exitSeen)
            return;
        finish();
    }
}
