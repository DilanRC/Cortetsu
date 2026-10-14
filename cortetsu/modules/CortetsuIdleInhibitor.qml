pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property alias enabled: state.enabled
    readonly property alias enabledSince: state.enabledSince

    onEnabledChanged: {
        if (enabled)
            state.enabledSince = new Date();
    }

    PersistentProperties {
        id: state
        property bool enabled: false
        property date enabledSince
        reloadableId: "cortetsu-idle-inhibitor"
    }

    // Keep-awake pauses Cortetsu's own idle actions (lock, screen off, idle
    // suspend; see IdleMonitors). Hyprland ignores idle inhibitors on
    // layer-shell surfaces, which is what this used to create, so the old
    // toggle did nothing. It is not a logind inhibitor: Suspend still works.
    CortetsuShortcut {
        name: "keepAwake"
        description: "Toggle keep-awake"
        onPressed: root.enabled = !root.enabled
    }

    IpcHandler {
        target: "keepAwake"
        function toggle(): bool { root.enabled = !root.enabled; return root.enabled; }
        function enable(): void { root.enabled = true; }
        function disable(): void { root.enabled = false; }
        function isEnabled(): bool { return root.enabled; }
    }
}
