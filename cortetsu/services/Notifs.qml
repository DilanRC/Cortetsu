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
    readonly property var notClosed: list.filter(item => !item.closed)
    readonly property var popups: list.filter(item => item.popup)
    property bool dnd: false
    property bool dndLoaded: false
    property bool loaded: true

    function hasFullscreen(): bool {
        return CortetsuHypr.monitors.values.some(m => m?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1));
    }
    function shouldShowPopup(): bool {
        return !dnd && !CortetsuShellState.anySidebarOpen() && !(CortetsuConfig.suppressNotificationsInFullscreen && hasFullscreen());
    }
    function remove(item: NotifData): void { list = list.filter(entry => entry !== item); item.destroy(); }
    function clear(): void { list.slice().forEach(item => item.close()); }

    FileView {
        id: dndStorage
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/notification-status.json`
        watchChanges: true
        printErrors: false
        onLoaded: { try { root.dnd = JSON.parse(text()).dnd === true; } catch (_) { root.dnd = false; } root.dndLoaded = true; }
        onFileChanged: { try { root.dnd = JSON.parse(text()).dnd === true; } catch (_) { root.dnd = false; } }
        onLoadFailed: { root.dndLoaded = true; setText(JSON.stringify({dnd: false})); }
    }
    onDndChanged: if (dndLoaded) dndStorage.setText(JSON.stringify({dnd}))

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
            const item = notifComponent.createObject(root, {notification, popup: root.shouldShowPopup()});
            root.list = [item, ...root.list];
        }
    }
    Component { id: notifComponent; NotifData {} }
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
