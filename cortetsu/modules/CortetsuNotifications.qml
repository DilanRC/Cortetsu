pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "CortetsuNotificationModel.js" as HistoryModel

// First-party notification history/DND facade. Reads two XDG-state files
// (cortetsu/notifs.json, cortetsu/notification-status.json) reactively via
// FileView, and routes mutations through the cortetsu-notifications binary
// (deterministic, unit-tested in cortetsu/tests/test-notifications.py)
// rather than embedding JSON-editing logic in QML. No coupling to the
// upstream shared-config singletons. See docs/NOTIFICATIONS.md for the
// DBus ownership boundary this facade respects.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`
    property int count: 0
    property var history: []
    property bool dnd: false
    property bool loaded: false
    property bool statusReady: false
    property bool historyReady: false
    property var clearState: null
    property bool clearStorageReady: false
    property bool historyAwaitingClear: false

    function readNotifications(): void {
        historyAwaitingClear = false;
        if (clearState === null || clearState.pending) { historyReady = false; return; }
        const entries = HistoryModel.parseHistory(notifications.text());
        historyReady = entries !== null;
        if (entries === null) return;
        history = entries;
        count = history.length;
    }

    function applyClearState(next: var): void {
        const observed = HistoryModel.observeClear(clearState, next);
        clearStorageReady = observed !== null;
        if (observed === null) return;
        clearState = observed.state;
        if (observed.clear || clearState.pending) { history = []; count = 0; }
        if (historyAwaitingClear) readNotifications();
        else if (notifications) notifications.reload();
    }

    function dismiss(id: var): void {
        Quickshell.execDetached(["cortetsu-notifications", "dismiss", String(id)]);
    }

    function clear(): void {
        Quickshell.execDetached(["cortetsu-notifications", "clear"]);
    }

    function setDnd(enabled: bool): void {
        Quickshell.execDetached(["cortetsu-notifications", "dnd", enabled ? "on" : "off"]);
    }

    function toggleDnd(): void {
        Quickshell.execDetached(["cortetsu-notifications", "dnd", "toggle"]);
    }

    FileView {
        id: clearStorage
        path: `${root.stateRoot}/cortetsu/notifs-clear.json`
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.applyClearState(JSON.parse(text())); }
            catch (_) { root.clearStorageReady = false; }
        }
        onFileChanged: reload()
        onLoadFailed: {
            if (root.clearState === null) root.applyClearState({revision: 0, pending: false});
            else if (root.historyAwaitingClear) root.readNotifications();
            root.clearStorageReady = false;
        }
    }
    Timer {
        running: !root.clearStorageReady
        interval: 1000
        repeat: true
        onTriggered: clearStorage.reload()
    }

    FileView {
        id: notifications
        path: `${root.stateRoot}/cortetsu/notifs.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.historyAwaitingClear = true;
            clearStorage.reload();
        }
        onFileChanged: reload()
        onLoadFailed: {
            root.historyReady = false;
        }
    }

    // A missing file cannot be watched; Notifs creates it on its first save,
    // so retry until it exists.
    Timer {
        running: !root.historyReady
        interval: 1000
        repeat: true
        onTriggered: notifications.reload()
    }

    FileView {
        id: status

        path: `${root.stateRoot}/cortetsu/notification-status.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            const state = HistoryModel.parseDnd(text());
            root.statusReady = state !== null;
            if (state !== null) { root.dnd = state.dnd; root.loaded = true; }
        }
        onFileChanged: reload()
        onLoadFailed: {
            root.statusReady = false;
        }
    }

    Timer {
        running: !root.statusReady
        interval: 1000
        repeat: true
        onTriggered: status.reload()
    }

    IpcHandler {
        target: "cortetsu-notifications"
        function clear(): void { root.clear(); }
        function dismiss(id: string): void { root.dismiss(id); }
        function setDnd(enabled: bool): void { root.setDnd(enabled); }
        function toggleDnd(): void { root.toggleDnd(); }
        function isDndEnabled(): bool { return root.dnd; }
        function count(): int { return root.count; }
    }
}
