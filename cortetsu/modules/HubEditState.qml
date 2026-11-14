pragma Singleton

import QtQml
import "HubAnchor.js" as HubAnchor

// The Hub's edit mode, for one monitor at a time: where the Hub was when it
// began, and where it will go if the move is saved. Nothing changes until
// save(); cancel() leaves the Hub where it was. Settings, the IPC and the
// edit surface (HubEditMode.qml) all go through here.
QtObject {
    id: root

    // The output being edited; "" while the edit mode is closed.
    property string monitor: ""
    readonly property bool active: monitor.length > 0
    property string original: HubAnchor.fallback
    property string pending: HubAnchor.fallback

    signal saved(string monitor, string id)

    function begin(monitorName: string): bool {
        if (typeof monitorName !== "string" || monitorName.length === 0)
            return false;
        original = CortetsuConfig.bottomHub.anchorFor(monitorName);
        pending = original;
        monitor = monitorName;
        return true;
    }

    function target(id: string): void {
        if (active && HubAnchor.valid(id))
            pending = id;
    }

    // The place the Hub had before 3.0, and the one it falls back to.
    function restoreDefault(): void {
        target(HubAnchor.fallback);
    }

    // The new place is this monitor's own (CortetsuConfig.bottomHub.anchors).
    function save(): bool {
        if (!active)
            return false;
        const name = monitor;
        const id = pending;
        monitor = "";
        if (id !== original)
            CortetsuConfig.bottomHub.setAnchor(name, id);
        saved(name, id);
        return true;
    }

    function cancel(): void {
        monitor = "";
    }
}
