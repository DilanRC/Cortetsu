pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// Every call «Atajos y teclados» makes to cortetsu-keybinds. Nothing runs
// while the surface is closed: `watch` (hotplug) lives only while `active`,
// and the other commands run on demand and exit.
Item {
    id: root

    property bool active: false
    // How long the surface records before giving up. Hyprland's own fail-safe
    // releases the keyboard a little later, in case the shell never does.
    readonly property int captureTimeoutMs: 15000
    readonly property int captureFailSafeMs: captureTimeoutMs + 5000

    readonly property string helper:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-keybinds"

    property var inventory: null
    property var keysData: null
    property var bindings: []
    property string version: ""
    property string inventoryError: ""
    property string keysError: ""
    property string bindingsError: ""
    readonly property bool loading: bindingsProcess.running || keysProcess.running
    readonly property bool writing: applyProcess.running
    readonly property bool capturing: captureProcess.running

    readonly property var keyboards: inventory?.keyboards ?? []
    readonly property var deviceKeys: keysData?.devices ?? []
    readonly property var spare: keysData?.spare ?? []
    // Layout keysym of each physical key, by XKB scan code (Linux code + 8),
    // for naming keys Qt has no constant for while capturing.
    readonly property var keysymByScanCode: {
        const map = {};
        for (const device of deviceKeys)
            for (const key of device.keys ?? [])
                if (key.keysym && map[key.code + 8] === undefined)
                    map[key.code + 8] = key.keysym;
        return map;
    }

    signal previewed(var result)
    signal applied(var result)
    signal captureAnswered(string verb, var result)

    function parse(text: string): var {
        try {
            return JSON.parse(text.trim());
        } catch (error) {
            return null;
        }
    }

    function refresh(): void {
        if (!bindingsProcess.running)
            bindingsProcess.running = true;
        if (!keysProcess.running)
            keysProcess.running = true;
    }

    // `args`: "set ID CHORD" or "add-app CHORD", as CaptureFlow builds them.
    function preview(args: var): void {
        previewProcess.command = [helper, "preview", ...args];
        previewProcess.running = true;
    }

    // `args` is a writing command (set, delete, reset, add-app); `reviewed`
    // is the version the person saw in the preview. A change in between is
    // refused by the helper with nothing written.
    function apply(args: var, reviewed: string): void {
        if (applyProcess.running)
            return;
        applyProcess.command = [helper, "--expect", reviewed].concat(args);
        applyProcess.running = true;
    }

    // One call at a time, in order: an `end` asked for while `begin` is still
    // running waits for it instead of being dropped.
    property string queuedCapture: ""

    function capture(verb: string): void {
        if (captureProcess.running) {
            queuedCapture = verb;
            return;
        }
        captureProcess.verb = verb;
        captureProcess.command = verb === "begin" ? [helper, "capture", "begin", String(captureFailSafeMs)] : [helper, "capture", "end"];
        captureProcess.running = true;
    }

    // The surface is going away mid-capture: tell Hyprland without waiting.
    // Its own timer would end the capture anyway; this ends it now.
    function releaseDetached(): void {
        Quickshell.execDetached([helper, "capture", "end"]);
    }

    onActiveChanged: if (active) refresh()

    // startup inventory: cortetsu:keyboards-watch
    Process {
        id: watchProcess
        running: root.active
        command: [root.helper, "watch"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim().length === 0)
                    return; // heartbeat
                const message = root.parse(line);
                if (!message?.ok) {
                    root.inventoryError = message?.error?.message ?? qsTr("No se pudo leer el inventario de teclados");
                    return;
                }
                const changed = root.inventory?.fingerprint !== message.fingerprint;
                root.inventory = message;
                root.inventoryError = "";
                if (changed && message.event === "changed" && !keysProcess.running)
                    keysProcess.running = true;
            }
        }
    }

    Process {
        id: keysProcess
        command: [root.helper, "keys"]
        stdout: StdioCollector {
            onStreamFinished: {
                const message = root.parse(text);
                root.keysError = message?.ok ? "" : (message?.error?.message ?? qsTr("No se pudieron leer las teclas"));
                if (message?.ok)
                    root.keysData = message;
            }
        }
    }

    Process {
        id: bindingsProcess
        command: [root.helper, "bindings"]
        stdout: StdioCollector {
            onStreamFinished: {
                const message = root.parse(text);
                root.bindingsError = message?.ok ? "" : (message?.error?.message ?? qsTr("No se pudieron leer los atajos"));
                if (message?.ok) {
                    root.bindings = message.bindings ?? [];
                    root.version = message.version ?? "";
                }
            }
        }
    }

    Process {
        id: previewProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const message = root.parse(text);
                root.previewed(message?.ok ? message : { valid: false, problem: message?.error?.message ?? qsTr("No se pudo revisar el cambio") });
            }
        }
    }

    Process {
        id: applyProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const message = root.parse(text);
                root.applied(message ?? { ok: false, error: qsTr("El cambio no respondió") });
                root.refresh();
            }
        }
    }

    Process {
        id: captureProcess
        property string verb: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const message = root.parse(text);
                root.captureAnswered(captureProcess.verb, message ?? { ok: false, error: { message: qsTr("Hyprland no respondió") } });
                const queued = root.queuedCapture;
                root.queuedCapture = "";
                if (queued.length > 0)
                    Qt.callLater(() => root.capture(queued));
            }
        }
    }
}
