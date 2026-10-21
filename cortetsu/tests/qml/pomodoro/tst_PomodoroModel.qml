import QtQuick
import QtTest
import "../../../modules/pomodoro/PomodoroModel.js" as Model

// What the Pomodoro card shows for a helper state and a clock reading.
TestCase {
    name: "PomodoroModel"

    readonly property real now: 1000000000

    function test_idle_shows_a_full_focus_session() {
        compare(Model.timeLeft({}, now), "25:00");
        compare(Model.timeLeft({ phase: "IDLE", focusMinutes: 50 }, now), "50:00");
        compare(Model.progress({ phase: "IDLE" }, now), 0);
        compare(Model.primaryCommand({ phase: "IDLE" }), "start");
        compare(Model.primaryCommand(undefined), "start");
    }

    function test_running_counts_down_to_zero() {
        const state = { phase: "FOCUS", focusMinutes: 25, targetEndTimestamp: (now + 25 * 60000) / 1000 };
        compare(Model.timeLeft(state, now), "25:00");
        compare(Model.timeLeft(state, now + 400), "25:00");
        compare(Model.timeLeft(state, now + 1000), "24:59");
        compare(Model.timeLeft(state, now + 25 * 60000 - 1), "00:01");
        compare(Model.timeLeft(state, now + 25 * 60000), "00:00");
        compare(Model.timeLeft(state, now + 99 * 60000), "00:00");
        compare(Model.progress(state, now), 0);
        compare(Model.progress(state, now + 12.5 * 60000), 0.5);
        compare(Model.progress(state, now + 30 * 60000), 1);
        compare(Model.primaryCommand(state), "pause");
    }

    function test_breaks_use_their_length() {
        const shortBreak = { phase: "BREAK", shortBreakMinutes: 10, targetEndTimestamp: (now + 5 * 60000) / 1000 };
        compare(Model.progress(shortBreak, now), 0.5);
        verify(Model.isBreak("LONG_BREAK") && Model.isBreak("BREAK") && !Model.isBreak("FOCUS"));
        const longBreak = { phase: "LONG_BREAK", targetEndTimestamp: (now + 15 * 60000) / 1000 };
        compare(Model.phaseDurationMs(longBreak, "LONG_BREAK"), 15 * 60000);
        compare(Model.progress(longBreak, now), 0);
    }

    function test_paused_freezes_the_remaining_time() {
        const state = { phase: "PAUSED", pausedPhase: "BREAK", pausedRemainingMs: 90000, shortBreakMinutes: 5 };
        compare(Model.timeLeft(state, now), "01:30");
        compare(Model.timeLeft(state, now + 3600000), "01:30");
        compare(Model.progress(state, now), 0.7);
        compare(Model.countedPhase(state), "BREAK");
        compare(Model.primaryCommand(state), "resume");
    }

    function test_corrupt_values_fall_back() {
        compare(Model.timeLeft({ phase: "FOCUS", targetEndTimestamp: "x" }, now), "00:00");
        compare(Model.phaseDurationMs({ focusMinutes: "x" }, "FOCUS"), 25 * 60000);
        compare(Model.phaseDurationMs({ focusMinutes: -3 }, "FOCUS"), 60000);
        compare(Model.timeLeft({ phase: "PAUSED", pausedRemainingMs: -5 }, now), "00:00");
    }

    // Announcements: one toast per phase end, none for what a previous shell
    // already showed (the old reader toasted the last event on every reload).
    function test_announcements_are_shown_once() {
        const started = 2e18;
        const old = { sequence: started - 5e9, title: "Descanso terminado", message: "Listo" };
        let reading = Model.announcement(old, 0, started);
        verify(!reading.toast);
        compare(reading.sequence, old.sequence);
        reading = Model.announcement(old, reading.sequence, started);
        verify(!reading.toast);
        const fresh = { sequence: started + 1e9, title: "Sesión de concentración completada", message: "Toca un descanso corto" };
        reading = Model.announcement(fresh, reading.sequence, started);
        verify(reading.toast);
        reading = Model.announcement(fresh, reading.sequence, started);
        verify(!reading.toast, "a reload of the same event repeated the toast");
        verify(!Model.announcement({ sequence: started + 2e9 }, reading.sequence, started).toast);
        verify(!Model.announcement(null, 0, started).toast);
        compare(Model.announcement({ sequence: 0 }, 0, started).sequence, 0);
    }
}
