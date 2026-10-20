import QtQuick
import Quickshell
import Quickshell.Io
import "modules/calendar"
import "modules/pomodoro"
import "services"

// Runs as the shell.qml of a composed runtime (Quickshell registers singletons
// only inside the config folder), set up by test-calendar-pomodoro-services.py.
// Drives the real CalendarService and Pomodoro singletons against files in a
// private HOME and prints
// SERVICES_PASS or SERVICES_FAIL. Every step waits at most 5 s for its result.
ShellRoot {
    id: shell

    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME")}/cortetsu`
    readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME")}/cortetsu`
    property int step: 0
    property bool acted: false
    property real deadline: 0
    property int toastsBefore: 0
    property real freshSequence: 0
    property var log: []

    function event(sequence, title): string {
        return JSON.stringify({ sequence: sequence, title: title, message: "fixture" }) + "\n";
    }

    function cache(count: int): string {
        const events = [];
        for (let index = 0; index < count; ++index)
            events.push({ eventId: `e${index}`, calendarId: "c", calendarName: "C", title: `E${index}`,
                          start: "2026-10-20", end: "2026-10-21", allDay: true });
        return JSON.stringify({ schema: 1, calendars: [{ calendarId: "c", calendarName: "C" }], events: events });
    }

    // [name, action, condition]
    readonly property var steps: [
        ["an announcement older than the shell is not shown", () => {}, () => CortetsuToaster.toasts.length === 0 && Pomodoro.phase === "IDLE", 600],
        ["start goes through the helper", () => Pomodoro.run("start"), () => Pomodoro.phase === "FOCUS" && Pomodoro.running],
        ["the state file is re-read when it changes", () => stateWriter.setText(JSON.stringify({ schema: 2, phase: "BREAK", targetEndTimestamp: Date.now() / 1000 + 60, completedSessions: 1, focusMinutes: 50 })),
            () => Pomodoro.phase === "BREAK" && Pomodoro.state.completedSessions === 1],
        ["a new announcement is one toast", () => {
                shell.toastsBefore = CortetsuToaster.toasts.length;
                shell.freshSequence = Date.now() * 1e6 + 1e9;
                eventWriter.setText(shell.event(shell.freshSequence, "Descanso terminado"));
            }, () => CortetsuToaster.toasts.length === shell.toastsBefore + 1],
        ["rewriting the same announcement does not repeat it", () => eventWriter.setText(shell.event(shell.freshSequence, "Descanso terminado")),
            () => CortetsuToaster.toasts.length === shell.toastsBefore + 1, 800],
        ["the event cache is read", () => cacheWriter.setText(shell.cache(1)), () => CalendarService.events.length === 1],
        ["the event cache is re-read when it changes", () => cacheWriter.setText(shell.cache(2)), () => CalendarService.events.length === 2],
        ["a sync reloads the cache and reports its status", () => CalendarService.requestSync(true),
            () => CalendarService.events.length === 3 && CalendarService.syncStatus === "Actualizado" && !CalendarService.syncing],
        ["reset keeps the user's durations", () => Pomodoro.run("reset"),
            () => Pomodoro.phase === "IDLE" && Pomodoro.state.focusMinutes === 50]
    ]

    FileView { id: stateWriter; path: `${shell.stateDir}/pomodoro.json`; printErrors: false }
    FileView { id: eventWriter; path: `${shell.stateDir}/pomodoro-notification.json`; printErrors: false }
    FileView { id: cacheWriter; path: `${shell.cacheDir}/calendar-events.json`; printErrors: false }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (shell.step >= shell.steps.length) {
                stop();
                console.log("SERVICES_PASS " + shell.log.join(" | "));
                Qt.quit();
                return;
            }
            const [name, action, condition, settle] = shell.steps[shell.step];
            if (!shell.acted) {
                shell.acted = true;
                shell.deadline = Date.now() + (settle ?? 5000);
                action();
                return;
            }
            const ok = condition();
            // A settle step must still hold when its time is up; a wait step passes as soon as it holds.
            if ((ok && settle === undefined) || (settle !== undefined && Date.now() >= shell.deadline && ok)) {
                shell.log = shell.log.concat([`ok ${name}`]);
                shell.step += 1;
                shell.acted = false;
            } else if (Date.now() >= shell.deadline) {
                stop();
                console.error(`SERVICES_FAIL ${name}: phase=${Pomodoro.phase} toasts=${CortetsuToaster.toasts.length} events=${CalendarService.events.length} status=${CalendarService.syncStatus}`);
                Qt.quit();
            }
        }
    }
}
