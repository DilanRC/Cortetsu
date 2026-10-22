pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../modules"
import "../modules/CortetsuNotificationModel.js" as HistoryModel

Singleton {
    id: root
    property var list: []
    property int revision: 0
    property bool dnd: false
    property bool dndLoaded: false
    property bool dndStorageReady: false
    property var clearState: null
    property bool clearStorageReady: false
    property bool historyAwaitingClear: false
    property bool snapshotPending: false
    property bool snapshotInFlight: false
    property var snapshotBatch: null
    property string snapshotPayload: ""
    property string snapshotReadback: ""
    property string lastWriteError: ""
    property bool loaded: false
    // Ids from the last confirmed snapshot. A file edit closes only these;
    // owner readback uses the separately frozen in-flight batch.
    property var savedIds: []
    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu`

    function hasFullscreen(): bool {
        return CortetsuHypr.monitors.values.some(m => m?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1));
    }
    function shouldShowPopup(): bool {
        return dndLoaded && dndStorageReady && !dnd && !CortetsuShellState.anySidebarOpen() && !(CortetsuConfig.suppressNotificationsInFullscreen && hasFullscreen());
    }
    function refreshCollections(): void {
        revision += 1;
        if (loaded) saveTimer.restart();
    }
    function notClosed(): var {
        root.revision;
        return root.list.filter(item => !item.closed);
    }
    function popups(): var {
        root.revision;
        return root.list.filter(item => item.popup);
    }
    function remove(item: NotifData): void {
        list = list.filter(entry => entry !== item);
        refreshCollections();
        item.destroy();
    }
    function clear(): void {
        Quickshell.execDetached(["cortetsu-notifications", "clear"]);
    }
    function applyClearState(next: var): void {
        const observed = HistoryModel.observeClear(clearState, next);
        clearStorageReady = observed !== null;
        if (observed === null) { lastWriteError = "INVALID_CLEAR_STATE"; return; }
        clearState = observed.state;
        if (observed.clear) {
            list.slice().forEach(item => item.close());
            savedIds = [];
        }
        // A pending marker was durably written before []. Until the owner
        // completes that clear, the old disk array must not restore entries.
        if (historyAwaitingClear) consumeHistory();
        else if (history) history.reload();
    }
    function consumeHistory(): void {
        if (clearState === null) return;
        historyAwaitingClear = false;
        if (loaded) applyExternalEdit();
        else restoreSnapshot();
    }
    function saveSnapshot(): void {
        if (snapshotInFlight) { snapshotPending = true; return; }
        if (clearState === null) { lastWriteError = "CLEAR_STATE_UNAVAILABLE"; return; }
        const entries = notClosed().map(item => ({
            id: item.key, time: item.time.getTime(), summary: item.summary, body: item.body,
            appIcon: item.appIcon, appName: item.appName, image: item.image,
            expireTimeout: item.expireTimeout, urgency: item.urgency, resident: item.resident,
            hasActionIcons: item.hasActionIcons
        }));
        snapshotBatch = HistoryModel.prepareBatch(savedIds, entries, clearState.revision);
        if (snapshotBatch === null) { lastWriteError = "INVALID_HISTORY"; return; }
        snapshotPayload = JSON.stringify(snapshotBatch);
        snapshotReadback = "";
        snapshotInFlight = true;
        snapshotWriter.stdinEnabled = true;
        snapshotWriter.running = true;
    }
    function readSnapshot(): var {
        return HistoryModel.parseHistory(history.text());
    }
    function restoreSnapshot(): void {
        if (clearState === null) return;
        // Restored entries have no D-Bus object: actions cannot be invoked
        // after a restart, so they come back as plain history items.
        const restored = (clearState.pending ? [] : (readSnapshot() ?? [])).map(entry => notifComponent.createObject(root, {
            key: String(entry.id), time: new Date(entry.time ?? Date.now()),
            summary: entry.summary ?? "", body: entry.body ?? "", appIcon: entry.appIcon ?? "",
            appName: entry.appName ?? "", image: entry.image ?? "", expireTimeout: entry.expireTimeout ?? 5000,
            urgency: entry.urgency ?? NotificationUrgency.Normal, resident: entry.resident === true,
            hasActionIcons: entry.hasActionIcons === true
        }));
        restored.forEach(item => item.updateTimeStr());
        savedIds = restored.map(item => item.key);
        list = [...list, ...restored];
        loaded = true;
        refreshCollections();
    }
    function applyReconciliation(result: var): bool {
        if (result === null) return false;
        const removed = new Set(result.removed);
        list.filter(item => removed.has(item.key)).forEach(item => item.close());
        // Updating this before closing removed IDs loses the comparison base
        // when a CLI dismissal races the merge process's stdout/readback.
        savedIds = result.savedIds;
        return true;
    }
    function applyExternalEdit(): void {
        if (snapshotInFlight || clearState === null || clearState.pending) return;
        // Invalid/unreadable state is never interpreted as a clear.
        applyReconciliation(HistoryModel.externalEdit(savedIds, readSnapshot()));
    }

    FileView {
        id: clearStorage
        path: `${root.stateDir}/notifs-clear.json`
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.applyClearState(JSON.parse(text())); }
            catch (_) { root.clearStorageReady = false; root.lastWriteError = "INVALID_CLEAR_STATE"; }
        }
        onFileChanged: reload()
        onLoadFailed: {
            // Before the first explicit clear there is no marker. Never
            // reset an already confirmed revision if that file disappears.
            if (root.clearState === null) root.applyClearState({revision: 0, pending: false});
            else if (root.historyAwaitingClear) root.consumeHistory();
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
        id: dndStorage
        path: `${root.stateDir}/notification-status.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            const state = HistoryModel.parseDnd(text());
            root.dndStorageReady = state !== null;
            if (state !== null) { root.dnd = state.dnd; root.dndLoaded = true; }
        }
        onFileChanged: reload()
        onLoadFailed: root.dndStorageReady = false
    }
    // startup inventory: cortetsu:notification-status-ensure
    Process {
        id: initializeDnd
        command: ["cortetsu-notifications", "dnd", "ensure"]
        running: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: dndStorage.reload()
    }
    Timer {
        interval: 1000
        repeat: true
        running: !root.dndStorageReady
        onTriggered: dndStorage.reload()
    }
    function setDnd(enabled: bool): void {
        Quickshell.execDetached(["cortetsu-notifications", "dnd", enabled ? "on" : "off"]);
    }
    function toggleDnd(): void {
        Quickshell.execDetached(["cortetsu-notifications", "dnd", "toggle"]);
    }

    // startup inventory: cortetsu:notification-history-merge
    Process {
        id: snapshotWriter
        command: ["cortetsu-notifications", "merge"]
        stdout: StdioCollector { onStreamFinished: root.snapshotReadback = text }
        stderr: StdioCollector {}
        onStarted: {
            write(root.snapshotPayload);
            stdinEnabled = false;
            root.snapshotPayload = "";
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.snapshotInFlight) return;
            if (exitCode === 0 && exitStatus === 0) {
                try {
                    const verified = HistoryModel.parseHistory(root.snapshotReadback);
                    if (!root.applyReconciliation(HistoryModel.reconcile(root.snapshotBatch, verified)))
                        throw new Error("invalid owner response");
                    root.lastWriteError = "";
                } catch (_) { root.lastWriteError = "APPLY_VERIFICATION_FAILED"; }
            } else {
                root.lastWriteError = "OWNER_UNAVAILABLE";
            }
            root.snapshotInFlight = false;
            root.snapshotBatch = null;
            // Reads during the write are deferred to this point. The file may
            // now contain a newer CLI dismissal than this process's response.
            history.reload();
            if (root.snapshotPending) { root.snapshotPending = false; saveTimer.restart(); }
        }
    }
    Timer {
        running: root.snapshotInFlight
        interval: 7000
        onTriggered: {
            root.lastWriteError = "DEADLINE_EXCEEDED";
            root.snapshotInFlight = false;
            root.snapshotBatch = null;
            snapshotWriter.running = false;
            history.reload();
            if (root.snapshotPending) { root.snapshotPending = false; saveTimer.restart(); }
        }
    }

    // notifs.json is the snapshot CortetsuNotifications and the
    // cortetsu-notifications CLI read and edit; modules cannot import this
    // singleton, so the file is the only bridge between them.
    FileView {
        id: history
        path: `${root.stateDir}/notifs.json`
        blockLoading: true
        watchChanges: true
        printErrors: false
        // Read the matching clear marker before interpreting this array. A
        // first-ever clear may create the marker before its watcher exists.
        onLoaded: { root.historyAwaitingClear = true; clearStorage.reload(); }
        onLoadFailed: if (!root.loaded) { root.historyAwaitingClear = true; clearStorage.reload(); }
        onFileChanged: reload()
    }
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: root.saveSnapshot()
    }

    NotificationServer {
        id: server
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: notification => {
            notification.tracked = true;
            // The server restarts its ids at 1, so the snapshot key also
            // carries the arrival time to stay unique against restored items.
            const item = notifComponent.createObject(root, {
                notification, key: `${Date.now()}-${notification.id}`, popup: root.shouldShowPopup()
            });
            root.list = [item, ...root.list];
            root.refreshCollections();
        }
    }
    Component { id: notifComponent; NotifData {} }
    CortetsuShortcut {
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: root.clear()
    }
    IpcHandler {
        target: "notifs"
        function clear(): void { root.clear(); }
        function inspect(): string {
            return JSON.stringify(root.list.map(item => ({
                id: item.notificationId,
                summary: item.summary,
                popup: item.popup,
                closed: item.closed,
                resident: item.resident,
                urgency: item.urgency,
                expireTimeout: item.expireTimeout,
                actions: item.actions.length
            })));
        }
        function isDndEnabled(): bool { return root.dnd; }
        function toggleDnd(): void { root.toggleDnd(); }
        function enableDnd(): void { root.setDnd(true); }
        function disableDnd(): void { root.setDnd(false); }
    }
}
