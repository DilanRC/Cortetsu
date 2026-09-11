pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root
    focus: true
    required property var screenState
    property var payload: ({})
    property var selection: ({})
    property var pomodoro: ({})
    property date selectedDate: new Date()
    property double nowMs: Date.now()
    property string syncStatus: ""
    readonly property string cachePath: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/cortetsu/calendar-events.json`
    readonly property string selectionPath: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/cortetsu/calendar-selection.json`
    readonly property string pomodoroPath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/pomodoro.json`
    readonly property string calendarHelperPath: `${Quickshell.env("HOME")}/.local/bin/cortetsu-calendar`
    readonly property string pomodoroHelperPath: `${Quickshell.env("HOME")}/.local/bin/cortetsu-pomodoro`
    readonly property var selectedEvents: (payload.events || []).filter(event => eventOccursOnDate(event, selectedDate))

    function eventDate(event): date {
        if (event.allDay) {
            const parts = event.start.split("-");
            return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        }
        return new Date(event.start);
    }
    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate();
    }
    function daysInMonth(d: date): int { return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate(); }
    function firstOffset(d: date): int { return (new Date(d.getFullYear(), d.getMonth(), 1).getDay() + 6) % 7; }
    function dayStart(value: date): date { return new Date(value.getFullYear(), value.getMonth(), value.getDate()); }
    function eventEndDate(event): date {
        if (event.allDay) {
            const parts = event.end.split("-");
            return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 0, 0, 0, -1);
        }
        return new Date(new Date(event.end).getTime() - 1);
    }
    function eventOccursOnDate(event, value: date): bool {
        const target = dayStart(value).getTime();
        return target >= dayStart(eventDate(event)).getTime()
            && target <= dayStart(eventEndDate(event)).getTime();
    }
    function eventsForDay(day: int): var {
        const target = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), day);
        return (payload.events || []).filter(event => eventOccursOnDate(event, target));
    }
    function isToday(day: int): bool { return day > 0 && sameDay(new Date(), new Date(selectedDate.getFullYear(), selectedDate.getMonth(), day)); }
    function isSelected(day: int): bool { return day > 0 && day === selectedDate.getDate(); }
    function friendlyName(calendar): string { return calendar.primary ? qsTr("Personal") : calendar.calendarName; }
    function eventTime(event): string {
        if (event.allDay) return qsTr("All day");
        return `${Qt.formatTime(eventDate(event), "HH:mm")}–${Qt.formatTime(new Date(event.end), "HH:mm")}`;
    }
    function isBreakPhase(phase): bool { return phase === "BREAK" || phase === "LONG_BREAK"; }
    function isActivePhase(phase): bool { return phase === "FOCUS" || isBreakPhase(phase); }
    function phaseDurationMs(phase): double {
        if (phase === "LONG_BREAK") return Number(pomodoro.longBreakMinutes || 15) * 60000;
        if (phase === "BREAK") return Number(pomodoro.shortBreakMinutes || 5) * 60000;
        return Number(pomodoro.focusMinutes || 25) * 60000;
    }
    function remainingMs(): double {
        if (pomodoro.phase === "PAUSED") return Math.max(0, Number(pomodoro.pausedRemainingMs || 0));
        if (isActivePhase(pomodoro.phase)) return Math.max(0, Number(pomodoro.targetEndTimestamp || 0) * 1000 - nowMs);
        return phaseDurationMs("FOCUS");
    }
    function timeLeft(): string {
        const ms = remainingMs();
        return `${String(Math.floor(ms / 60000)).padStart(2, "0")}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}`;
    }
    function progress(): double {
        const phase = pomodoro.phase === "PAUSED" ? (pomodoro.pausedPhase || "FOCUS") : pomodoro.phase;
        if (!isActivePhase(phase)) return 0;
        return Math.max(0, Math.min(1, 1 - remainingMs() / Math.max(1, phaseDurationMs(phase))));
    }
    function phaseLabel(): string {
        if (pomodoro.phase === "FOCUS") return qsTr("Focus");
        if (pomodoro.phase === "BREAK") return qsTr("Short break");
        if (pomodoro.phase === "LONG_BREAK") return qsTr("Long break");
        if (pomodoro.phase === "PAUSED") return qsTr("Paused");
        return qsTr("Ready to focus");
    }
    function runPomodoro(command: string): void {
        if (pomoProcess.running) return;
        const next = Object.assign({}, pomodoro);
        const now = Date.now();
        root.nowMs = now;
        if (command === "start") {
            next.phase = "FOCUS"; next.targetEndTimestamp = now / 1000 + Number(next.focusMinutes || 25) * 60;
            next.pausedRemainingMs = 0; next.pausedPhase = "FOCUS";
        } else if (command === "pause" && isActivePhase(next.phase)) {
            next.pausedRemainingMs = Math.max(0, Number(next.targetEndTimestamp || 0) * 1000 - now);
            next.pausedPhase = next.phase; next.targetEndTimestamp = 0; next.phase = "PAUSED";
        } else if (command === "resume" && next.phase === "PAUSED") {
            next.phase = next.pausedPhase || "FOCUS";
            next.targetEndTimestamp = now / 1000 + Number(next.pausedRemainingMs || 0) / 1000;
            next.pausedRemainingMs = 0;
        } else if (command === "skip" && isBreakPhase(next.phase)) {
            next.phase = "FOCUS"; next.targetEndTimestamp = now / 1000 + Number(next.focusMinutes || 25) * 60;
            next.pausedRemainingMs = 0; next.pausedPhase = "FOCUS";
        } else if (command === "reset") {
            next.phase = "IDLE"; next.targetEndTimestamp = 0; next.pausedRemainingMs = 0;
            next.pausedPhase = "FOCUS"; next.completedSessions = 0;
        }
        root.pomodoro = next;
        pomoProcess.command = [root.pomodoroHelperPath, command];
        pomoProcess.running = true;
    }
    function changeMonth(delta: int): void { selectedDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth() + delta, 1); }
    function loadCalendar(): void { try { payload = JSON.parse(cache.text()); } catch (_) { payload = {}; } }
    function loadSelection(): void { try { selection = JSON.parse(selectionFile.text()); } catch (_) { selection = {}; } }
    function loadPomodoro(): void { try { pomodoro = JSON.parse(pomodoroFile.text()); } catch (_) { pomodoro = {}; } }
    function load(): void { loadCalendar(); loadSelection(); loadPomodoro(); }
    function requestCalendarSync(force = false): void {
        if (calendarSync.running) return;
        syncStatus = qsTr("Syncing…");
        calendarSync.command = force ? [calendarHelperPath, "sync", "--force"] : [calendarHelperPath, "sync"];
        calendarSync.running = true;
    }

    Component.onCompleted: {
        load();
        if (screenState && screenState.cortetsuState && screenState.cortetsuState.calendar)
            requestCalendarSync();
    }
    Connections {
        target: root.screenState ? root.screenState.cortetsuState : null
        function onCalendarChanged(): void {
            if (root.screenState && root.screenState.cortetsuState && root.screenState.cortetsuState.calendar)
                root.requestCalendarSync();
        }
    }
    FileView { id: cache; path: root.cachePath; watchChanges: true; printErrors: false; onLoaded: root.loadCalendar(); onFileChanged: root.loadCalendar() }
    FileView { id: selectionFile; path: root.selectionPath; watchChanges: true; printErrors: false; onLoaded: root.loadSelection(); onFileChanged: root.loadSelection() }
    FileView { id: pomodoroFile; path: root.pomodoroPath; watchChanges: true; printErrors: false; onLoaded: root.loadPomodoro(); onFileChanged: pomodoroReload.restart() }
    Process {
        id: calendarSync
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    syncStatus = result.status === "ok" ? qsTr("Up to date")
                        : result.status === "cached" ? qsTr("Recently synced")
                        : result.status === "partial" ? qsTr("Partial sync")
                        : result.status === "auth_required" ? qsTr("Sign-in required")
                        : result.status === "sync_in_progress" ? qsTr("Sync already running")
                        : qsTr("Sync failed");
                } catch (_) { syncStatus = qsTr("Sync failed"); }
                root.loadCalendar();
            }
        }
    }
    Process { id: selectionProcess; onExited: { root.loadSelection(); root.requestCalendarSync(true); } }
    Process {
        id: pomoProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.pomodoro = JSON.parse(text.trim()); }
                catch (_) { pomodoroReload.restart(); }
            }
        }
        onExited: pomodoroReload.restart()
    }
    Timer { id: pomodoroReload; interval: 60; repeat: false; onTriggered: root.loadPomodoro() }
    Timer { interval: 1000; repeat: true; running: root.isActivePhase(pomodoro.phase); onTriggered: root.nowMs = Date.now() }
    Keys.onEscapePressed: root.screenState.cortetsuState?.setRetained("calendar", false)

    CortetsuSurface { outlined: false;
        anchors.fill: parent
        radius: CortetsuDesign.radiusLarge
        color: CortetsuDesign.colorSurface

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingComfortable
            spacing: CortetsuDesign.spacingStandard

            RowLayout {
                Layout.fillWidth: true
                CortetsuText { Layout.fillWidth: true; text: qsTr("Calendar"); textSize: CortetsuTypography.titleLargePx; color: CortetsuDesign.colorOnSurface }
                CortetsuText { visible: root.syncStatus.length > 0; text: root.syncStatus; textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                CortetsuButton { compact: true; icon: calendarSync.running ? "sync" : "refresh"; label: ""; tooltipText: qsTr("Sync calendar"); disabled: calendarSync.running; onClicked: root.requestCalendarSync(true) }
                CortetsuButton { compact: true; icon: "close"; label: ""; tooltipText: qsTr("Close Calendar"); onClicked: root.screenState.cortetsuState?.setRetained("calendar", false) }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: CortetsuDesign.spacingComfortable

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 430
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuButton { compact: true; icon: "chevron_left"; label: ""; tooltipText: qsTr("Previous month"); onClicked: root.changeMonth(-1) }
                        CortetsuText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Qt.formatDate(root.selectedDate, "MMMM yyyy"); textSize: CortetsuTypography.titleMediumPx; color: CortetsuDesign.colorOnSurface }
                        CortetsuButton { compact: true; icon: "today"; label: qsTr("Today"); onClicked: root.selectedDate = new Date() }
                        CortetsuButton { compact: true; icon: "chevron_right"; label: ""; tooltipText: qsTr("Next month"); onClicked: root.changeMonth(1) }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 290
                        columns: 7
                        Repeater { model: [qsTr("Mo"), qsTr("Tu"), qsTr("We"), qsTr("Th"), qsTr("Fr"), qsTr("Sa"), qsTr("Su")]; delegate: CortetsuText { required property var modelData; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx } }
                        Repeater {
                            model: 42
                            delegate: Item {
                                id: dayCell
                                required property int index
                                Layout.fillWidth: true; Layout.fillHeight: true
                                readonly property int day: { const value = index - root.firstOffset(root.selectedDate) + 1; return value > 0 && value <= root.daysInMonth(root.selectedDate) ? value : 0; }
                                CortetsuSurface { outlined: false; anchors.centerIn: parent; width: 34; height: 34; radius: 17; color: root.isSelected(parent.day) ? CortetsuDesign.colorPrimary : (root.isToday(parent.day) ? CortetsuDesign.colorPrimaryContainer : "transparent") }
                                CortetsuText { anchors.centerIn: parent; text: parent.day || ""; color: root.isSelected(parent.day) ? CortetsuDesign.colorOnPrimary : (root.isToday(parent.day) ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface); textSize: CortetsuTypography.labelMediumPx }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; spacing: 2
                                    Repeater {
                                        model: dayCell.day ? root.eventsForDay(dayCell.day).slice(0, 3) : []
                                        delegate: Rectangle { required property var modelData; width: 4; height: 4; radius: 2; color: modelData.calendarColor || CortetsuDesign.colorTertiary }
                                    }
                                    CortetsuText { visible: dayCell.day && root.eventsForDay(dayCell.day).length > 3; text: "+"; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                                }
                                MouseArea { anchors.fill: parent; enabled: parent.day > 0; hoverEnabled: true; onClicked: root.selectedDate = new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), parent.day) }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact
                        Repeater {
                            model: root.payload.calendars || []
                            delegate: CortetsuSurface { outlined: false;
                                required property var modelData
                                readonly property bool enabled: (root.selection.enabled || []).includes(modelData.calendarId)
                                implicitWidth: chipRow.implicitWidth + CortetsuDesign.spacingStandard * 2; implicitHeight: 30; radius: 999
                                color: enabled ? CortetsuDesign.colorSecondaryContainer : CortetsuDesign.colorSurfaceHigh
                                RowLayout {
                                    id: chipRow; anchors.centerIn: parent; spacing: CortetsuDesign.spacingCompact
                                    Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: modelData.calendarColor || CortetsuDesign.colorSecondary }
                                    CortetsuText { text: root.friendlyName(modelData); color: parent.parent.enabled ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelMediumPx }
                                    CortetsuText { text: parent.parent.enabled ? "✓" : "+"; color: parent.parent.enabled ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelMediumPx }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { selectionProcess.command = [Quickshell.env("HOME") + "/.local/bin/cortetsu-calendar", "set-selection", modelData.calendarId, parent.enabled ? "false" : "true"]; selectionProcess.running = true; } }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 350
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuSurface { outlined: false;
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSurfaceHigh
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: CortetsuDesign.spacingStandard; spacing: CortetsuDesign.spacingCompact
                            CortetsuText { Layout.fillWidth: true; text: Qt.formatDate(root.selectedDate, "dddd, MMMM d"); textSize: CortetsuTypography.titleMediumPx; color: CortetsuDesign.colorOnSurface }
                            CortetsuText { text: root.selectedEvents.length ? `${root.selectedEvents.length} ${root.selectedEvents.length === 1 ? qsTr("event") : qsTr("events")}` : qsTr("Your day is clear"); color: CortetsuDesign.colorPrimary; textSize: CortetsuTypography.labelMediumPx }
                            ColumnLayout {
                                visible: !root.selectedEvents.length; Layout.fillWidth: true; Layout.fillHeight: true; spacing: CortetsuDesign.spacingCompact
                                Item { Layout.fillHeight: true }
                                CortetsuIcon { Layout.alignment: Qt.AlignHCenter; text: "event_available"; color: CortetsuDesign.colorOnSurfaceVariant; iconSize: CortetsuTypography.iconLargePx }
                                CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("No events"); color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.titleSmallPx }
                                CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Take the time for yourself."); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
                                Item { Layout.fillHeight: true }
                            }
                            ListView {
                                visible: root.selectedEvents.length > 0; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: CortetsuDesign.spacingCompact; model: root.selectedEvents
                                delegate: RowLayout {
                                    required property var modelData; width: parent.width; spacing: CortetsuDesign.spacingCompact
                                    Rectangle { implicitWidth: 5; implicitHeight: eventDetails.implicitHeight; radius: 3; color: modelData.calendarColor || CortetsuDesign.colorPrimary }
                                    ColumnLayout {
                                        id: eventDetails; Layout.fillWidth: true; spacing: 1
                                        CortetsuText { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.bodyLargePx }
                                        CortetsuText { Layout.fillWidth: true; text: `${root.eventTime(modelData)}  ·  ${root.friendlyName(modelData)}`; elide: Text.ElideRight; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                                        CortetsuText { visible: !!modelData.location; Layout.fillWidth: true; text: modelData.location; elide: Text.ElideRight; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                                    }
                                }
                            }
                        }
                    }

                    CortetsuSurface { outlined: false;
                        Layout.fillWidth: true
                        Layout.preferredHeight: 154
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSecondaryContainer
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: CortetsuDesign.spacingStandard; spacing: CortetsuDesign.spacingCompact
                            RowLayout { Layout.fillWidth: true; CortetsuText { Layout.fillWidth: true; text: root.phaseLabel(); color: CortetsuDesign.colorOnSecondaryContainer; textSize: CortetsuTypography.labelLargePx } CortetsuText { text: qsTr("%1 sessions").arg(Number(pomodoro.completedSessions || 0)); color: CortetsuDesign.colorOnSecondaryContainer; textSize: CortetsuTypography.labelSmallPx } }
                            CortetsuText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.timeLeft(); color: CortetsuDesign.colorOnSecondaryContainer; textSize: CortetsuTypography.titleLargePx }
                            CortetsuProgressBar {
                                Layout.fillWidth: true
                                value: root.progress()
                                barHeight: 5
                                barRadius: 3
                                trackColor: CortetsuDesign.colorSecondary
                                fillColor: CortetsuDesign.colorOnSecondaryContainer
                                motionDuration: CortetsuDesign.motionFastMs
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                CortetsuButton {
                                    visible: root.isBreakPhase(pomodoro.phase)
                                    compact: true
                                    icon: "skip_next"
                                    label: qsTr("Skip break")
                                    onClicked: root.runPomodoro("skip")
                                }
                                CortetsuButton {
                                    compact: true
                                    icon: root.isActivePhase(pomodoro.phase) ? "pause" : "play_arrow"
                                    label: root.isActivePhase(pomodoro.phase)
                                        ? qsTr("Pause")
                                        : pomodoro.phase === "PAUSED" ? qsTr("Resume") : qsTr("Start")
                                    onClicked: root.runPomodoro(root.isActivePhase(pomodoro.phase)
                                        ? "pause" : pomodoro.phase === "PAUSED" ? "resume" : "start")
                                }
                                CortetsuButton {
                                    compact: true
                                    icon: "restart_alt"
                                    label: qsTr("Reset")
                                    onClicked: root.runPomodoro("reset")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
