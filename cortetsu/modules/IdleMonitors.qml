pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"

Scope {
    id: root
    required property var lock
    readonly property bool hasPlayer: Players.list.some(player => player.isPlaying)
    readonly property bool isCharging: !CortetsuPower.onBattery
    readonly property bool enabled: !(CortetsuConfig.idleInhibitWhenAudio && hasPlayer)
        && !(CortetsuConfig.idleInhibitWhenCharging && isCharging)

    function handleIdleAction(action: var): void {
        if (action === "lock")
            root.lock.requestLock();
        else if (typeof action === "string")
            CortetsuHypr.dispatch(action);
        else if (Array.isArray(action))
            Quickshell.execDetached(action);
    }

    Connections {
        target: CortetsuSession
        function onAboutToSleep(): void {
            if (CortetsuConfig.idleLockBeforeSleep)
                root.lock.requestLock();
        }
    }

    // Delays sleep until the compositor confirms the lock, so resume never shows the desktop.
    // ponytail: logind caps the delay (InhibitDelayMaxSec, 5 s by default); a lock slower than that sleeps unlocked.
    // startup inventory: cortetsu:session-sleep-lock
    Process {
        id: sleepLock
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Cortetsu", "--why=Lock before sleep", "sleep", "infinity"]
        running: CortetsuConfig.idleLockBeforeSleep && !root.lock.lock.secure
    }

    Variants {
        model: CortetsuConfig.idleTimeouts
        IdleMonitor {
            required property var modelData
            enabled: root.enabled && (modelData.enabled ?? true)
                && (!(modelData.inhibitWhenAudio ?? false) || !root.hasPlayer)
                && (!(modelData.inhibitWhenCharging ?? false) || !root.isCharging)
            timeout: modelData.timeout ?? 900000
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
