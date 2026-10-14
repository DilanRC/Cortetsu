pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Sampling runs only while a visible view holds a reference.
    property int consumers: 0

    property real used: 0
    property real total: 0
    readonly property real percentage: total > 0 ? used / total : 0

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const values = {};
            for (const line of text().split("\n")) {
                const match = line.match(/^([^:]+):\s+(\d+)/);
                if (match)
                    values[match[1]] = Number(match[2]);
            }
            root.total = values.MemTotal ?? 0;
            root.used = Math.max(0, root.total - (values.MemAvailable ?? values.MemFree ?? 0));
        }
    }

    Timer {
        running: root.consumers > 0
        triggeredOnStart: true
        repeat: true
        interval: 2000
        onTriggered: meminfo.reload()
    }
}
