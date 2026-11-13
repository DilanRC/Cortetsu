pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../components/misc"

Scope {
    id: root
    property alias lock: sessionLock
    readonly property bool lockReady: sessionLock.locked

    function requestLock(): void {
        sessionLock.locked = true;
    }

    WlSessionLock {
        id: sessionLock
        LockSurface { lock: sessionLock; pam: pam; keyboard: keyboard }
    }

    Pam { id: pam; lock: sessionLock }

    // The keyboard's layout and lock keys, read once for every monitor's
    // surface and only while the session is locked.
    QtObject {
        id: keyboard
        property string layout: ""
        property bool capsLock: false
        property bool numLock: false

        function update(raw: string): void {
            try {
                const keyboards = JSON.parse(raw)?.keyboards ?? [];
                const main = keyboards.find(device => device.main) || keyboards[0];
                if (!main)
                    return;
                layout = String(main.active_keymap ?? main.activeKeymap ?? "").trim();
                capsLock = Boolean(main.capsLock ?? main.caps_lock ?? false);
                numLock = Boolean(main.numLock ?? main.num_lock ?? false);
            } catch (_) {
                layout = "";
                capsLock = false;
                numLock = false;
            }
        }
    }

    // startup inventory: cortetsu:lock-keyboard-probe (on demand, while locked)
    Process {
        id: keyboardProbe
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: keyboard.update(text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: sessionLock.locked
        triggeredOnStart: true
        onTriggered: if (!keyboardProbe.running)
            keyboardProbe.running = true
    }

    CustomShortcut { name: "lock"; description: "Lock the current session"; onPressed: sessionLock.locked = true }

    IpcHandler {
        target: "lock"
        function lock(): void { root.requestLock() }
        function isLocked(): bool { return sessionLock.locked }
    }
}
