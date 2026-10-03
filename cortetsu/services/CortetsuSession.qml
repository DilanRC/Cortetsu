pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    signal aboutToSleep
    signal resumed

    // startup inventory: cortetsu:session-sleep-monitor
    Process {
        id: monitor
        command: ["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("boolean true"))
                    root.aboutToSleep();
                else if (line.includes("boolean false"))
                    root.resumed();
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
}
