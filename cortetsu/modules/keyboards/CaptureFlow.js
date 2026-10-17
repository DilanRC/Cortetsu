.pragma library

// The shortcut capture of «Atajos y teclados» as a reducer. next(state,
// event) returns a new state without side effects; effects(before, event,
// after) lists what the surface must do for that step. The surface runs the
// effects and feeds their outcome back as events.
//
//   idle ─start→ listening ─begun→ (armed) ─chord→ recovering ─released→
//   review ─previewed→ ─confirm→ applying ─applied→ verified
//   idle ─propose→ review (a chord known without recording)
//
// Alternatives: conflict (the preview or the apply refused the chord),
// failed (an effect failed), cancelled, and recovering: Hyprland is told to
// leave the capture submap and the flow waits until it says it did.
//
// `change` says what a confirmed chord does: {kind: "set", id} changes a
// shortcut, {kind: "add-app", app} adds an application shortcut.

var RESTING = ["idle", "verified", "conflict", "failed", "cancelled", "review"];

function initial() {
    return { phase: "idle", chord: "", held: [], message: "", preview: null, after: "",
             change: null, armed: false,
             // While recovering: where the flow goes once the submap is left,
             // and the message a cancel left for it.
             target: "", reason: "" };
}

function withPhase(state, phase, changes) {
    var next = { phase: phase, chord: state.chord, held: state.held, message: "",
                 preview: state.preview, after: state.after, change: state.change, armed: state.armed,
                 target: state.target, reason: state.reason };
    for (var key in changes)
        next[key] = changes[key];
    return next;
}

// After leaving the submap: where the flow was going.
function settled(state, phase, message) {
    return withPhase(state, phase, { held: [], message: message || "", armed: false, target: "", reason: "" });
}

function next(state, event) {
    var phase = state.phase;
    switch (event.type) {
    case "start":
        // Only from a resting phase: never while Hyprland is being changed.
        if (RESTING.indexOf(phase) < 0 || !event.change)
            return state;
        return withPhase(initial(), "listening", { change: event.change });
    case "begun":
        // Hyprland answered `capture begin`. Keys count only from here.
        if (phase !== "listening" || state.armed)
            return state;
        if (event.ok)
            return withPhase(state, "listening", { armed: true });
        return settled(state, "failed", event.message || "");
    case "propose":
        // A chord known without recording (a spare key's own keysym) goes
        // straight to review: nothing is held, so nothing to release.
        if (RESTING.indexOf(phase) < 0 || !event.change)
            return state;
        return withPhase(initial(), "review", { chord: event.chord, change: event.change });
    case "held":
        if (phase !== "listening" || !state.armed)
            return state;
        return withPhase(state, "listening", { held: event.held, message: event.message || "" });
    case "chord":
        if (phase !== "listening" || !state.armed)
            return state;
        // The submap is left first; review starts once Hyprland confirms.
        return withPhase(state, "recovering", { chord: event.chord, held: [], target: "review" });
    case "released":
        if (phase !== "recovering")
            return state;
        if (!event.ok)
            return settled(state, "failed", event.message || "");
        if (state.target === "review")
            return settled(state, "review", "");
        return settled(state, "cancelled", state.reason || "");
    case "previewed":
        if (phase !== "review")
            return state;
        if (!event.preview || !event.preview.valid)
            return withPhase(state, "conflict", { preview: event.preview,
                                                  message: (event.preview && event.preview.problem) || event.message || "" });
        return withPhase(state, "review", { preview: event.preview, after: event.preview.after });
    case "confirm":
        // Explicit confirmation of a valid preview, nothing else.
        if (phase !== "review" || !state.preview || !state.preview.valid)
            return state;
        return withPhase(state, "applying", {});
    case "applied":
        if (phase !== "applying")
            return state;
        if (event.ok)
            return withPhase(state, "verified", { message: event.message || "" });
        return withPhase(state, event.stale ? "conflict" : "failed", { message: event.message || "" });
    case "changed":
        // A reset or delete applied straight from its button.
        if (RESTING.indexOf(phase) < 0)
            return state;
        return withPhase(initial(), event.ok ? "verified" : "failed", { message: event.message || "" });
    case "cancel":
    case "timeout":
    case "closed": {
        var reason = event.message || "";
        if (phase === "listening")
            return withPhase(state, "recovering", { held: [], target: "cancelled", reason: reason });
        if (phase === "review" || phase === "conflict")
            return settled(state, "cancelled", reason);
        return state;
    }
    case "reset":
        if (RESTING.indexOf(phase) < 0)
            return state;
        return initial();
    }
    return state;
}

// What the surface does for one step, in order:
//   {do: "capture", verb: "begin" | "end"}  enter or leave the submap
//   {do: "countdown", run: bool}            the visible capture timeout
//   {do: "preview", args}                     ask whether the chord is free
//   {do: "apply", args, version}              write the reviewed chord
// `args` are the helper's arguments after `preview` or `--expect VERSION`.
function effects(before, event, after) {
    var out = [];
    if (after.phase === "listening" && before.phase !== "listening")
        out.push({ do: "capture", verb: "begin" });
    if (event.type === "begun" && after.armed && !before.armed)
        out.push({ do: "countdown", run: true });
    if (event.type === "begun" && after.phase === "failed")
        // A half-entered capture: leave it; the answer is ignored.
        out.push({ do: "capture", verb: "end" });
    if (after.phase === "recovering" && before.phase !== "recovering") {
        out.push({ do: "countdown", run: false });
        out.push({ do: "capture", verb: "end" });
    }
    // Every new chord in review is previewed, also a second proposal.
    if (after.phase === "review" && (before.phase !== "review" || event.type === "propose"))
        out.push({ do: "preview", chord: after.chord,
                   args: after.change.kind === "set" ? ["set", after.change.id, after.chord] : ["add-app", after.chord] });
    if (after.phase === "applying" && before.phase !== "applying")
        out.push({ do: "apply", version: after.preview.version, args: writeArgs(after.change, after.after) });
    return out;
}

function writeArgs(change, chord) {
    if (change.kind === "set")
        return ["set", change.id, chord];
    return ["add-app", change.app.id, change.app.name, change.app.execString, chord];
}

// Hyprland holds every global bind while this is true.
function holdsKeyboard(state) {
    return state.phase === "listening";
}

// A phase in which the surface must not start anything else.
function busy(state) {
    return state.phase === "applying" || state.phase === "recovering";
}
