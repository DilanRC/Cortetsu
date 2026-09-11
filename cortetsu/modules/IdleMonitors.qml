pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
            root.lock.locked = true;
        else if (action === "unlock")
            root.lock.unlock();
        else if (typeof action === "string")
            CortetsuHypr.dispatch(action);
        else if (Array.isArray(action))
            Quickshell.execDetached(action);
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
