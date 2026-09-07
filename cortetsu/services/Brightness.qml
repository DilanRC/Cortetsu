pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"

Singleton {
    id: root

    readonly property list<Monitor> monitors: variants.instances
    property string backlightDevice: ""
    property int backlightMax: 0

    onBacklightDeviceChanged: {
        monitors.forEach(monitor => monitor.reload());
    }
    onBacklightMaxChanged: monitors.forEach(monitor => monitor.reload())

    readonly property Process discoverProcess: Process {
        command: ["brightnessctl", "-l", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.split("\n").find(item => item.split(",")[1] === "backlight");
                if (!line)
                    return;
                const fields = line.split(",");
                root.backlightDevice = fields[0] ?? "";
            }
        }
    }

    readonly property Process maxProcess: Process {
        command: ["cat", "/sys/class/backlight/" + root.backlightDevice + "/max_brightness"]
        running: root.backlightDevice.length > 0
        stdout: StdioCollector {
            onStreamFinished: {
                const maximum = Number(text.trim());
                root.backlightMax = Number.isFinite(maximum) ? maximum : 0;
            }
        }
    }

    Component.onCompleted: discoverProcess.running = true

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen) ?? null;
    }

    function getMonitor(query: string): var {
        if (query === "active")
            return monitors.find(m => CortetsuHypr.monitorFor(m.modelData)?.focused) ?? monitors[0] ?? null;
        if (query.startsWith("model:"))
            return monitors.find(m => m.modelData.model === query.slice(6)) ?? null;
        if (query.startsWith("serial:"))
            return monitors.find(m => m.modelData.serialNumber === query.slice(7)) ?? null;
        if (query.startsWith("id:"))
            return monitors.find(m => CortetsuHypr.monitorFor(m.modelData)?.id === Number(query.slice(3))) ?? null;
        return monitors.find(m => m.modelData.name === query) ?? null;
    }

    function increaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor) monitor.setBrightness(monitor.brightness + CortetsuConfig.brightnessIncrement);
    }
    function decreaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor) monitor.setBrightness(monitor.brightness - CortetsuConfig.brightnessIncrement);
    }

    Variants {
        id: variants
        model: Quickshell.screens
        Monitor {}
    }

    IpcHandler {
        target: "brightness"
        function get(): real { return root.getMonitor("active")?.brightness ?? -1; }
        function getFor(query: string): real { return root.getMonitor(query)?.brightness ?? -1; }
        function status(): string {
            const monitor = root.getMonitor("active");
            return JSON.stringify({ device: root.backlightDevice, maximum: root.backlightMax,
                supported: monitor?.supported ?? false, brightness: monitor?.brightness ?? -1 });
        }
        function set(value: string): string { return setFor("active", value); }
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor) return "Invalid monitor: " + query;
            let amount = Number(value);
            if (value.endsWith("%")) amount = Number(value.slice(0, -1)) / 100;
            else if (value.startsWith("+")) amount = monitor.brightness + Number(value.slice(1));
            else if (value.endsWith("-")) amount = monitor.brightness - Number(value.slice(0, -1));
            else if (value.includes("%") || value.includes("+") || value.includes("-")) return "Invalid brightness format: " + value;
            if (!Number.isFinite(amount)) return "Failed to parse value: " + value;
            monitor.setBrightness(amount);
            return `Set monitor ${monitor.modelData.name} brightness to ${monitor.brightness.toFixed(2)}`;
        }
    }

    component Monitor: QtObject {
        id: monitor
        required property ShellScreen modelData
        property real brightness: -1
        readonly property string monitorName: modelData?.name ?? ""
        readonly property bool supported: root.backlightDevice.length > 0 && root.backlightMax > 0
        readonly property Process readProcess: Process {
            command: monitor.monitorName.length > 0
                ? ["brightnessctl", "-d", root.backlightDevice, "g"]
                : ["true"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const raw = Number(text.trim());
                    monitor.brightness = monitor.supported && Number.isFinite(raw)
                        ? Math.max(0, Math.min(1, raw / root.backlightMax))
                        : -1;
                }
            }
        }
        readonly property Process writeProcess: Process {
            command: ["brightnessctl", "-d", root.backlightDevice, "s", String(Math.round(monitor.pendingBrightness * root.backlightMax))]
            onExited: monitor.readProcess.running = monitor.supported
        }
        property real pendingBrightness: 0
        readonly property Timer reloadTimer: Timer {
            interval: 50
            onTriggered: {
                readProcess.running = false;
                readProcess.running = monitor.supported;
            }
        }

        function reload(): void {
            if (!supported)
                brightness = -1;
            reloadTimer.restart();
        }

        function setBrightness(value: real): void {
            if (!supported)
                return;
            pendingBrightness = Math.max(0, Math.min(1, value));
            writeProcess.running = true;
        }
        Component.onCompleted: reload()
    }
}
