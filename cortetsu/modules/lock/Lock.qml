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
        signal unlock
        LockSurface { lock: sessionLock; pam: pam }
    }

    Pam { id: pam; lock: sessionLock }

    Loader {
        asynchronous: true
        active: true
        onLoaded: active = false
        sourceComponent: ScreencopyView { captureSource: Quickshell.screens[0] }
    }

    CustomShortcut { name: "lock"; description: "Lock the current session"; onPressed: sessionLock.locked = true }
    CustomShortcut { name: "unlock"; description: "Unlock the current session"; onPressed: sessionLock.unlock() }

    IpcHandler {
        target: "lock"
        function lock(): void { root.requestLock() }
        function unlock(): void { sessionLock.unlock() }
        function isLocked(): bool { return sessionLock.locked }
    }
}
