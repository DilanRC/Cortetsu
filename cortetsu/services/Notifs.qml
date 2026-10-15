pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../modules"

Singleton {
    id: root
    property var list: []
    property int revision: 0
    property bool dnd: false
    property bool dndLoaded: false
    property bool loaded: false
    // Ids written by the last snapshot save. A file edit (the
    // cortetsu-notifications CLI) closes only these, so a notification that
    // arrived after the save is never dropped by a stale snapshot.
    property var savedIds: []
    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu`

    function hasFullscreen(): bool {
        return CortetsuHypr.monitors.values.some(m => m?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1));
    }
    function shouldShowPopup(): bool {
        return !dnd && !CortetsuShellState.anySidebarOpen() && !(CortetsuConfig.suppressNotificationsInFullscreen && hasFullscreen());
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
    function clear(): void { list.slice().forEach(item => item.close()); }
    function saveSnapshot(): void {
        // The synchronous reload runs applyExternalEdit (onLoaded) first, so
        // a CLI edit that landed since the last save is not resurrected.
        // ponytail: an edit landing between this reload and setText is still
        // overwritten; the user can repeat it. No shared lock exists.
        history.reload();
        const entries = notClosed().map(item => ({
            id: item.key, time: item.time.getTime(), summary: item.summary, body: item.body,
            appIcon: item.appIcon, appName: item.appName, image: item.image,
            expireTimeout: item.expireTimeout, urgency: item.urgency, resident: item.resident,
            hasActionIcons: item.hasActionIcons
        }));
        savedIds = entries.map(entry => entry.id);
        history.setText(JSON.stringify(entries));
    }
    function readSnapshot(): var {
        try {
            const entries = JSON.parse(history.text());
            return Array.isArray(entries) ? entries : null;
        } catch (_) {
            return null;
        }
    }
    function restoreSnapshot(): void {
        // Restored entries have no D-Bus object: actions cannot be invoked
        // after a restart, so they come back as plain history items.
        const restored = (readSnapshot() ?? []).map(entry => notifComponent.createObject(root, {
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
    function applyExternalEdit(): void {
        // An unreadable file (a write caught halfway) is not an edit; reading
        // it as [] would dismiss every live notification.
        const entries = readSnapshot();
        if (entries === null)
            return;
        // An empty snapshot is a clear: it also covers notifications that
        // arrived after the last save.
        if (entries.length === 0) {
            clear();
            return;
        }
        const kept = new Set(entries.map(entry => String(entry.id)));
        const removed = new Set(savedIds.filter(id => !kept.has(id)));
        list.filter(item => removed.has(item.key)).forEach(item => item.close());
    }

    FileView {
        id: dndStorage
        path: `${root.stateDir}/notification-status.json`
        watchChanges: true
        printErrors: false
        onLoaded: { try { root.dnd = JSON.parse(text()).dnd === true; } catch (_) { root.dnd = false; } root.dndLoaded = true; }
        onFileChanged: reload()
        onLoadFailed: { root.dndLoaded = true; setText(JSON.stringify({dnd: false})); }
    }
    onDndChanged: if (dndLoaded) dndStorage.setText(JSON.stringify({dnd}))

    // notifs.json is the snapshot CortetsuNotifications and the
    // cortetsu-notifications CLI read and edit; modules cannot import this
    // singleton, so the file is the only bridge between them.
    FileView {
        id: history
        path: `${root.stateDir}/notifs.json`
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.loaded ? root.applyExternalEdit() : root.restoreSnapshot()
        onLoadFailed: if (!root.loaded) root.restoreSnapshot()
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
        function toggleDnd(): void { root.dnd = !root.dnd; }
        function enableDnd(): void { root.dnd = true; }
        function disableDnd(): void { root.dnd = false; }
    }
}
