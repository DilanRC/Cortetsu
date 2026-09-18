pragma Singleton

import Quickshell
import Quickshell.Networking
import QtQuick

/**
 * First-party network status service.
 *
 * Backed by Quickshell's native Quickshell.Networking module, which talks to
 * NetworkManager over DBus and exposes properties as Qt bindable properties
 * (org.freedesktop.NetworkManager PropertiesChanged signals drive updates).
 * No polling, no CLI subprocess, no upstream shell dependency.
 *
 * Contract (unchanged for consumers, e.g. BottomHub.qml):
 *   - active: { strength, ssid } for the connected Wi-Fi network, else null.
 *   - activeEthernet: { connected: true } when a wired device is connected, else null.
 *   - connecting: true while NetworkManager reports an in-flight (re)connection.
 */
Singleton {
    id: root

    property bool refreshing: false

    function refresh(): void {
        const device = root.wifiDevice;
        if (!device || root.refreshing)
            return;
        root.refreshing = true;
        device.scannerEnabled = false;
        // A queued turn is enough to force NetworkManager to restart its
        // scanner. This stays an explicit user action, not a polling loop.
        Qt.callLater(() => {
            if (root.wifiDevice)
                root.wifiDevice.scannerEnabled = true;
            root.refreshing = false;
        });
    }

    function deviceOfType(type): var {
        return (Networking.devices?.values ?? []).find(device => device.type === type) ?? null;
    }

    // Quickshell exposes Wi-Fi strength as a normalized 0..1 value. The
    // visual consumers and NetworkManager's UI contract use percentages.
    function strengthPercent(raw): int {
        let value = Number(raw);
        if (!isFinite(value))
            return 0;
        if (value >= 0 && value <= 1)
            value *= 100;
        return Math.max(0, Math.min(100, Math.round(value)));
    }

    readonly property var wifiDevice: deviceOfType(DeviceType.Wifi)
    readonly property var wiredDevice: deviceOfType(DeviceType.Wired)

    readonly property var activeWifiNetwork: wifiDevice
        ? (wifiDevice.networks?.values ?? []).find(network => network.connected) ?? null
        : null

    readonly property var active: activeWifiNetwork
        ? { strength: root.strengthPercent(activeWifiNetwork.signalStrength), ssid: activeWifiNetwork.name }
        : null

    readonly property var activeEthernet: (wiredDevice?.connected ?? false)
        ? { connected: true } : null

    readonly property bool connecting:
        (wifiDevice?.state === ConnectionState.Connecting)
        || (activeWifiNetwork?.stateChanging ?? false)
}
