pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

QtObject {
    id: root
    property bool popup: false
    property bool closed: false
    property bool interactionActive: false
    property var locks: new Set()
    property bool dismissalRequested: false
    property date time: new Date()
    property string timeStr: "now"
    property Notification notification
    property string notificationId: ""
    property string summary: ""
    property string body: ""
    property string appIcon: ""
    property string appName: ""
    property string image: ""
    property var hints: ({})
    property real expireTimeout: 5000
    property int urgency: NotificationUrgency.Normal
    property bool resident: false
    property bool hasActionIcons: false
    property list<var> actions: []
    readonly property Timer timeStrTimer: Timer { running: !root.closed; repeat: true; interval: 30000; onTriggered: root.updateTimeStr() }
    readonly property Timer timer: Timer {
        running: root.popup && root.expireTimeout > 0 && !root.interactionActive
        interval: root.expireTimeout
        onTriggered: root.popup = false
    }

    onPopupChanged: Notifs.refreshCollections()
    onClosedChanged: Notifs.refreshCollections()

    function updateTimeStr(): void {
        const minutes = Math.floor((Date.now() - root.time.getTime()) / 60000);
        if (minutes < 1) root.timeStr = "now";
        else if (minutes < 60) root.timeStr = `${minutes}m`;
        else if (minutes < 1440) root.timeStr = `${Math.floor(minutes / 60)}h`;
        else root.timeStr = `${Math.floor(minutes / 1440)}d`;
    }
    function lock(item: Item): void { locks.add(item); }
    function unlock(item: Item): void {
        locks.delete(item);
        if (closed && locks.size === 0)
            dismissAndRemove();
    }

    function dismissAndRemove(): void {
        if (dismissalRequested)
            return;

        dismissalRequested = true;
        if (notification)
            notification.dismiss();
        Notifs.remove(root);
    }

    function close(): void {
        if (closed)
            return;

        // Remove the live popup before the delegate destruction handshake.
        // Otherwise a dismissed notification stays in Notifs.popups() with
        // opacity 0 while the UI lock keeps the model item alive.
        popup = false;
        closed = true;
        if (locks.size === 0)
            dismissAndRemove();
    }

    Component.onCompleted: {
        if (!notification) return;
        notificationId = notification.id; summary = notification.summary; body = notification.body;
        appIcon = notification.appIcon; appName = notification.appName; image = notification.image;
        hints = notification.hints; expireTimeout = notification.expireTimeout; urgency = notification.urgency;
        resident = notification.resident; hasActionIcons = notification.hasActionIcons;
        actions = notification.actions.map(action => ({identifier: action.identifier, text: action.text, invoke: () => action.invoke()}));
    }
}
