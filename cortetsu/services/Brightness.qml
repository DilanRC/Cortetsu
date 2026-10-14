pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../modules"

// Backlight per screen. A kernel backlight belongs to the connector it is
// registered under (amdgpu_bl2 lives in card2-eDP-1), so each screen only ever
// drives its own panel. A screen without one, such as HDMI on the dGPU, is
// unsupported: no gamma emulation and no borrowing the internal panel.
Singleton {
    id: root

    readonly property list<Monitor> monitors: variants.instances
    // The one screen source; tests replace it with plain objects.
    property var screens: Quickshell.screens
    // connector name -> { device, maximum }
    property var backlights: ({})

    // A hotplug or a late driver can add or drop a backlight; both probes are
    // sysfs and brightnessctl reads that never touch the dGPU.
    onScreensChanged: probeBacklights()

    QtObject {
        id: probe
        property var connectors: ({})
        property var maximum: ({})
        property bool connectorsLoaded: false
        property bool maximumLoaded: false
    }

    function rebuild(): void {
        // Both probes, or a firmware fallback could claim a kernel backlight.
        if (!probe.connectorsLoaded || !probe.maximumLoaded)
            return;
        const next = {};
        const unplaced = [];
        for (const device of Object.keys(probe.maximum)) {
            const entry = { device: device, maximum: probe.maximum[device] };
            const connector = probe.connectors[device] ?? "";
            if (connector.length)
                next[connector] = entry;
            else
                unplaced.push(entry);
        }
        // Firmware backlights (acpi_video, vendor WMI) are not children of a
        // connector. They can only belong to the internal panel, and only
        // when there is exactly one candidate on each side.
        const panels = [...screens].map(screen => screen.name)
            .filter(name => /^(eDP|LVDS|DSI)-/.test(name) && !next[name]);
        if (unplaced.length === 1 && panels.length === 1)
            next[panels[0]] = unplaced[0];
        backlights = next;
    }

    // startup inventory: cortetsu:brightness-connector (one-shot service load)
    readonly property Process connectorProcess: Process {
        command: ["find", "/sys/class/backlight", "-mindepth", "1", "-maxdepth", "1", "-printf", "%f\t%l\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const connectors = {};
                for (const line of text.split("\n")) {
                    const [device, target] = line.split("\t");
                    const match = /\/card\d+-([^/]+)\/[^/]+$/.exec(target ?? "");
                    if (device && match)
                        connectors[device] = match[1];
                }
                probe.connectors = connectors;
                probe.connectorsLoaded = true;
                root.rebuild();
            }
        }
    }

    // startup inventory: cortetsu:brightness-discovery (one-shot service load)
    readonly property Process discoverProcess: Process {
        command: ["brightnessctl", "-l", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const maximum = {};
                for (const line of text.split("\n")) {
                    const fields = line.split(",");
                    const value = Number(fields[4]);
                    if (fields[1] === "backlight" && fields[0].length && value > 0)
                        maximum[fields[0]] = value;
                }
                probe.maximum = maximum;
                probe.maximumLoaded = true;
                root.rebuild();
            }
        }
    }

    function probeBacklights(): void {
        if (!connectorProcess.running)
            connectorProcess.running = true;
        if (!discoverProcess.running)
            discoverProcess.running = true;
    }

    Component.onCompleted: probeBacklights()

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

    // The keys act on the focused screen. On a screen without a backlight they
    // do nothing rather than dim a different panel.
    function increaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor) monitor.step(CortetsuConfig.brightnessIncrement);
    }
    function decreaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor) monitor.step(-CortetsuConfig.brightnessIncrement);
    }

    CortetsuShortcut {
        name: "brightnessUp"
        description: "Raise the brightness of the focused screen"
        onPressed: root.increaseBrightness()
    }

    CortetsuShortcut {
        name: "brightnessDown"
        description: "Lower the brightness of the focused screen"
        onPressed: root.decreaseBrightness()
    }

    Variants {
        id: variants
        model: root.screens
        Monitor {}
    }

    IpcHandler {
        target: "brightness"
        function get(): real { return root.getMonitor("active")?.brightness ?? -1; }
        function getFor(query: string): real { return root.getMonitor(query)?.brightness ?? -1; }
        function status(): string {
            const describe = monitor => ({
                screen: monitor?.monitorName ?? "",
                device: monitor?.device ?? "",
                maximum: monitor?.maximum ?? 0,
                supported: monitor?.supported ?? false,
                brightness: monitor?.brightness ?? -1
            });
            return JSON.stringify(Object.assign(describe(root.getMonitor("active")),
                                                { screens: root.monitors.map(describe) }));
        }
        function set(value: string): string { return setFor("active", value); }
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor) return "Invalid monitor: " + query;
            if (!monitor.supported) return `Monitor ${monitor.monitorName} has no brightness control`;
            let amount = Number(value);
            if (value.endsWith("%")) amount = Number(value.slice(0, -1)) / 100;
            else if (value.startsWith("+")) amount = monitor.brightness + Number(value.slice(1));
            else if (value.endsWith("-")) amount = monitor.brightness - Number(value.slice(0, -1));
            else if (value.includes("%") || value.includes("+") || value.includes("-")) return "Invalid brightness format: " + value;
            if (!Number.isFinite(amount)) return "Failed to parse value: " + value;
            monitor.setBrightness(amount);
            return `Set monitor ${monitor.monitorName} brightness to ${monitor.pendingBrightness.toFixed(2)}`;
        }
    }

    component Monitor: QtObject {
        id: monitor
        required property var modelData
        readonly property string monitorName: modelData?.name ?? ""
        readonly property var backlight: root.backlights[monitorName] ?? null
        readonly property string device: backlight?.device ?? ""
        readonly property int maximum: backlight?.maximum ?? 0
        readonly property bool supported: device.length > 0 && maximum > 0
        // Last value read back from the device; -1 when unsupported or unread.
        property real brightness: -1
        property real pendingBrightness: 0
        property bool writeQueued: false

        // Deferred: this handler can run before the command binding has
        // picked up the new device. A queued value belonged to the old one.
        onDeviceChanged: {
            writeQueued = false;
            Qt.callLater(reload);
        }

        // startup inventory: cortetsu:brightness-read
        readonly property Process readProcess: Process {
            command: ["brightnessctl", "-d", monitor.device, "g"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const raw = Number(text.trim());
                    monitor.brightness = monitor.supported && text.trim().length && Number.isFinite(raw)
                        ? Math.max(0, Math.min(1, raw / monitor.maximum))
                        : -1;
                }
            }
            onExited: {
                if (monitor.readQueued) {
                    monitor.readQueued = false;
                    Qt.callLater(() => monitor.readProcess.running = true);
                } else if (!monitor.writeProcess.running && !monitor.writeQueued) {
                    monitor.settling = false;
                }
            }
        }
        readonly property Process writeProcess: Process {
            command: ["brightnessctl", "-d", monitor.device, "s", String(Math.round(monitor.pendingBrightness * monitor.maximum))]
            onExited: {
                if (monitor.writeQueued) {
                    monitor.writeQueued = false;
                    Qt.callLater(() => monitor.writeProcess.running = true);
                    return;
                }
                monitor.reload();
            }
        }
        // From a requested change until its read-back lands, steps build on
        // the requested level, not on a reading that is about to be replaced.
        property bool settling: false
        property bool readQueued: false

        function reload(): void {
            if (!supported) {
                brightness = -1;
                return;
            }
            if (readProcess.running)
                readQueued = true;
            else
                readProcess.running = true;
        }

        function setBrightness(value: real): void {
            if (!supported)
                return;
            pendingBrightness = Math.max(0, Math.min(1, value));
            settling = true;
            // Repeated key presses and slider drags keep only the latest value.
            if (writeProcess.running)
                writeQueued = true;
            else
                writeProcess.running = true;
        }

        function step(delta: real): void {
            const base = settling ? pendingBrightness : brightness;
            // Not read yet: a step from an unknown level could black the panel.
            if (!supported || base < 0)
                return;
            setBrightness(base + delta);
        }
        Component.onCompleted: reload()
    }
}
