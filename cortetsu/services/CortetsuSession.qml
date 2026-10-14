pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    signal aboutToSleep
    signal resumed

    // logind's answer per sleep mode: yes, no, challenge, inhibited or na.
    // "" is unknown (not probed yet, or the probe failed); requests are then
    // allowed and logind has the last word.
    readonly property string canSuspend: suspendProbe.answer
    readonly property string canHibernate: hibernateProbe.answer
    readonly property string canSuspendThenHibernate: suspendThenHibernateProbe.answer
    readonly property bool suspendAvailable: available("suspend")
    readonly property bool hibernateAvailable: available("hibernate")

    readonly property var modes: ({
        suspend: { probe: suspendProbe, verb: "suspend" },
        hibernate: { probe: hibernateProbe, verb: "hibernate" },
        suspendThenHibernate: { probe: suspendThenHibernateProbe, verb: "suspend-then-hibernate" }
    })

    function answer(mode: string): string {
        return modes[mode]?.probe.answer ?? "na";
    }

    function available(mode: string): bool {
        const value = answer(mode);
        return value === "" || value === "yes" || value === "challenge";
    }

    // Why a mode cannot be requested, in words a menu can show.
    function reason(mode: string): string {
        const value = answer(mode);
        if (value === "inhibited")
            return qsTr("Un programa lo está impidiendo");
        if (value === "na")
            return qsTr("No disponible en este equipo");
        if (value === "no")
            return qsTr("No permitido para este usuario");
        return "";
    }

    // Asks for exactly the mode named; nothing falls back to another mode
    // behind the caller's back. Returns false when logind said it would refuse.
    function request(mode: string): bool {
        if (!modes[mode] || !available(mode))
            return false;
        Quickshell.execDetached(["systemctl", modes[mode].verb]);
        return true;
    }

    function suspend(): bool { return request("suspend"); }
    function hibernate(): bool { return request("hibernate"); }

    function refreshCapabilities(): void {
        for (const probe of [suspendProbe, hibernateProbe, suspendThenHibernateProbe])
            if (!probe.running)
                probe.running = true;
    }

    // startup inventory: cortetsu:session-sleep-capability
    component CapabilityProbe: Process {
        id: probe
        required property string method
        property string answer: ""
        command: ["busctl", "--timeout=3", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager", method]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            // A failed or garbled probe leaves the previous answer in place.
            onStreamFinished: {
                const match = /^s "(\w+)"/.exec(text.trim());
                if (match)
                    probe.answer = match[1];
            }
        }
    }

    CapabilityProbe { id: suspendProbe; method: "CanSuspend" }
    CapabilityProbe { id: hibernateProbe; method: "CanHibernate" }
    CapabilityProbe { id: suspendThenHibernateProbe; method: "CanSuspendThenHibernate" }

    // startup inventory: cortetsu:session-sleep-monitor
    Process {
        id: monitor
        command: ["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("boolean true"))
                    root.aboutToSleep();
                else if (line.includes("boolean false")) {
                    root.resumed();
                    root.refreshCapabilities();
                }
            }
        }
        onExited: restart.running = true
        Component.onCompleted: running = true
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: monitor.running = true
    }

    Component.onCompleted: refreshCapabilities()
}
