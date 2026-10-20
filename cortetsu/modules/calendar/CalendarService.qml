pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// The Calendar data for every screen: the event cache and calendar selection
// written by cortetsu-calendar, and the one sync process. Before, every
// Calendar view (two per screen) kept its own copy and its own sync, and Bottom
// Hub ran a third: opening the calendar started overlapping syncs.
QtObject {
    id: root

    property var payload: ({})
    property var selection: ({})
    property string syncStatus: ""
    readonly property bool syncing: calendarSync.running
    readonly property var events: Array.isArray(payload.events) ? payload.events : []
    readonly property var calendars: Array.isArray(payload.calendars) ? payload.calendars : []
    readonly property var enabledCalendars: Array.isArray(selection.enabled) ? selection.enabled : []
    // The calendar surface is open on some screen. Opening it requests a sync;
    // the helper reuses a cache younger than 15 minutes.
    readonly property bool open: CortetsuShellState.allStates().some(state => !!state?.cortetsuState?.calendar)

    readonly property string cachePath: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/cortetsu/calendar-events.json`
    readonly property string selectionPath: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/cortetsu/calendar-selection.json`
    readonly property string helperPath: `${Quickshell.env("HOME")}/.local/bin/cortetsu-calendar`

    function parse(text: string): var {
        try {
            const value = JSON.parse(text);
            return value && typeof value === "object" ? value : {};
        } catch (_) {
            return {};
        }
    }

    function statusLabel(status: string): string {
        switch (status) {
        case "ok": return qsTr("Actualizado");
        case "cached": return qsTr("Sincronizado hace poco");
        case "partial": return qsTr("Sincronización parcial");
        case "auth_required": return qsTr("Hay que iniciar sesión");
        case "sync_in_progress": return qsTr("Ya se está sincronizando");
        default: return qsTr("No se pudo sincronizar");
        }
    }

    function requestSync(force: bool): void {
        if (calendarSync.running)
            return;
        syncStatus = qsTr("Sincronizando…");
        calendarSync.command = force ? [helperPath, "sync", "--force"] : [helperPath, "sync"];
        calendarSync.running = true;
    }

    function setCalendarEnabled(calendarId: string, enabled: bool): void {
        if (selectionProcess.running)
            return;
        selectionProcess.command = [helperPath, "set-selection", calendarId, enabled ? "true" : "false"];
        selectionProcess.running = true;
    }

    onOpenChanged: if (open) requestSync(false)

    property FileView cacheFile: FileView {
        path: root.cachePath
        watchChanges: true
        printErrors: false
        onLoaded: root.payload = root.parse(text())
        onLoadFailed: root.payload = ({})
        onFileChanged: reload()
    }

    property FileView selectionFile: FileView {
        path: root.selectionPath
        watchChanges: true
        printErrors: false
        onLoaded: root.selection = root.parse(text())
        onLoadFailed: root.selection = ({})
        onFileChanged: reload()
    }

    // startup inventory: cortetsu:calendar-sync
    property Process calendarSync: Process {
        stdout: StdioCollector {
            onStreamFinished: root.syncStatus = root.statusLabel(root.parse(text.trim()).status ?? "")
        }
        onExited: root.cacheFile.reload()
    }

    property Process selectionProcess: Process {
        onExited: {
            root.selectionFile.reload();
            root.requestSync(true);
        }
    }
}
