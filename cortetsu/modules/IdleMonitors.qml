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
    // A fullscreen window on the focused screen: a game on a controller or a
    // video, activity the compositor cannot see.
    readonly property bool hasFullscreen: CortetsuHypr.focusedFullscreen
    // ponytail: any output that is not an internal panel counts as external,
    // so a desktop or a virtual output never idle-suspends.
    readonly property bool hasExternalScreen: CortetsuHypr.monitors.values.some(monitor => !/^(eDP|LVDS|DSI)-/.test(monitor?.name ?? ""))
    // Keep-awake pauses every idle action. Audio, charging and fullscreen only
    // hold the screen and sleep: the lock still runs, so walking away from
    // music or a fullscreen window does not leave the session open.
    readonly property bool activityHold: (CortetsuConfig.idleInhibitWhenAudio && hasPlayer)
        || (CortetsuConfig.idleInhibitWhenCharging && isCharging)
        || (CortetsuConfig.idleInhibitWhenFullscreen && hasFullscreen)

    function allowed(entry: var): bool {
        if (CortetsuIdleInhibitor.enabled || !(entry.enabled ?? true))
            return false;
        if ((entry.inhibitWhenAudio ?? false) && hasPlayer)
            return false;
        if ((entry.inhibitWhenCharging ?? false) && isCharging)
            return false;
        if (entry.idleAction === "lock")
            return true;
        if (activityHold)
            return false;
        if (entry.idleAction === "suspend")
            return !hasExternalScreen && (!CortetsuConfig.idleSuspendOnBatteryOnly || !isCharging);
        return true;
    }

    function handleIdleAction(action: var): void {
        if (action === "lock")
            root.lock.requestLock();
        else if (action === "dpms" || action === "dpms-on")
            // Any key or pointer motion also turns the outputs back on
            // (misc.key_press_enables_dpms), so a lost "on" cannot strand them.
            CortetsuHypr.setDpms(action === "dpms-on");
        else if (action === "suspend")
            CortetsuSession.suspend();
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
        function onResumed(): void {
            nvidiaWakeDelay.restart();
        }
    }

    // After s2idle an output on the NVIDIA dGPU comes back without frames: its
    // first page flip never completes until the monitor cycles hot-plug, about
    // 30 s later. Turning those outputs off and on forces a modeset; on the
    // reference laptop frames returned 3 s after it. See docs/PHYSICAL_QA.md.
    property var nvidiaWake: []

    // logind reports the wake before Hyprland has reopened its DRM devices;
    // the cycle was measured with the output already stalled, 2 s in.
    Timer {
        id: nvidiaWakeDelay
        interval: 2000
        onTriggered: nvidiaOutputs.running = true
    }

    // startup inventory: cortetsu:resume-nvidia-outputs
    Process {
        id: nvidiaOutputs
        command: ["cortetsu-nvibrant", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let outputs = [];
                try {
                    outputs = JSON.parse(text).outputs ?? [];
                } catch (error) {
                    console.warn("cortetsu-idle: unreadable NVIDIA output list after resume");
                }
                root.nvidiaWake = outputs.filter(output => output.connected).map(output => output.connector);
                for (const name of root.nvidiaWake)
                    CortetsuHypr.setDpms(false, name);
                if (root.nvidiaWake.length > 0)
                    nvidiaDpmsOn.restart();
            }
        }
    }

    // A lost "on" cannot strand the output: any key turns it back on (misc.key_press_enables_dpms).
    Timer {
        id: nvidiaDpmsOn
        interval: 1000
        onTriggered: {
            for (const name of root.nvidiaWake)
                CortetsuHypr.setDpms(true, name);
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
            enabled: root.allowed(modelData)
            // idleTimeouts stores milliseconds; IdleMonitor counts seconds.
            // Passing 900000 straight through meant a 10-day lock timeout.
            timeout: (modelData.timeout ?? 900000) / 1000
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: {
                if (isIdle)
                    root.handleIdleAction(modelData.idleAction);
                else
                    root.handleIdleAction(modelData.returnAction ?? (modelData.idleAction === "dpms" ? "dpms-on" : undefined));
            }
        }
    }
}
