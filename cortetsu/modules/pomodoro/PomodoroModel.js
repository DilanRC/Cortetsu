.pragma library

// Read-only view of the state file written by cortetsu-pomodoro. The helper
// owns every transition; this file only derives what the UI shows from the
// state and a clock reading in milliseconds.

const DEFAULT_MINUTES = Object.freeze({ FOCUS: 25, BREAK: 5, LONG_BREAK: 15 });

function isBreak(phase) {
    return phase === "BREAK" || phase === "LONG_BREAK";
}

function isRunning(phase) {
    return phase === "FOCUS" || isBreak(phase);
}

function phaseDurationMs(state, phase) {
    const minutes = phase === "LONG_BREAK" ? state?.longBreakMinutes
        : phase === "BREAK" ? state?.shortBreakMinutes : state?.focusMinutes;
    return Math.max(1, Number(minutes) || DEFAULT_MINUTES[phase] || DEFAULT_MINUTES.FOCUS) * 60000;
}

// The phase the timer counts: the paused one while paused.
function countedPhase(state) {
    return state?.phase === "PAUSED" ? (state.pausedPhase || "FOCUS") : state?.phase;
}

function remainingMs(state, nowMs) {
    if (state?.phase === "PAUSED")
        return Math.max(0, Number(state.pausedRemainingMs) || 0);
    if (isRunning(state?.phase))
        return Math.max(0, (Number(state.targetEndTimestamp) || 0) * 1000 - nowMs);
    return phaseDurationMs(state, "FOCUS");
}

// mm:ss, rounded up so the display reaches 00:00 when the phase ends.
function timeLeft(state, nowMs) {
    const seconds = Math.ceil(remainingMs(state, nowMs) / 1000);
    return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

function progress(state, nowMs) {
    const phase = countedPhase(state);
    if (!isRunning(phase))
        return 0;
    return Math.max(0, Math.min(1, 1 - remainingMs(state, nowMs) / phaseDurationMs(state, phase)));
}

// The command of the main button: start, pause or resume.
function primaryCommand(state) {
    if (isRunning(state?.phase))
        return "pause";
    return state?.phase === "PAUSED" ? "resume" : "start";
}

// Reading of the announcement file. `consumed` is the last sequence read;
// only events written after the shell started (`startedNs`, nanoseconds like
// the helper's time.time_ns()) become a toast, so a reload never repeats one.
function announcement(event, consumed, startedNs) {
    const sequence = Number(event?.sequence) || 0;
    const fresh = sequence !== consumed;
    return {
        sequence: sequence,
        toast: fresh && sequence > startedNs && !!event?.title && !!event?.message
    };
}
