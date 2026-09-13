pragma Singleton

import QtQml
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool devicePresent: !!root.device
    readonly property bool ready: root.device?.ready === true
    readonly property bool laptopBattery: root.device?.isLaptopBattery === true
    readonly property real value: {
        const raw = Number(root.device?.percentage);
        return root.ready && Number.isFinite(raw)
            ? Math.max(0, Math.min(1, raw))
            : -1;
    }
    readonly property bool available: root.value >= 0
    readonly property bool hasBattery: root.laptopBattery && root.available
    readonly property int percent: root.hasBattery ? Math.round(root.value * 100) : -1
    readonly property bool onBattery: UPower.onBattery === true
    readonly property bool charging: root.hasBattery && [
        UPowerDeviceState.Charging,
        UPowerDeviceState.FullyCharged,
        UPowerDeviceState.PendingCharge
    ].includes(root.device?.state)
    readonly property bool critical: root.hasBattery && root.onBattery && root.value <= 0.2
    readonly property int timeToFull: Number(root.device?.timeToFull) || 0
    readonly property int timeToEmpty: Number(root.device?.timeToEmpty) || 0
}
