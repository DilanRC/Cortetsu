import QtQuick
import QtTest
import "../../../modules/keyboards/CaptureFlow.js" as Flow

TestCase {
    name: "CaptureFlow"

    readonly property var setSession: ({ kind: "set", id: "var:kbSession:0" })
    readonly property var addCalc: ({ kind: "add-app", app: { id: "calc", name: "Calc", execString: "calc" } })
    readonly property var valid: ({ valid: true, conflict: false, after: "SUPER + ALT + I", version: "v1" })

    function run(events) {
        let state = Flow.initial();
        for (const event of events)
            state = Flow.next(state, event);
        return state;
    }

    // The effects of one step, as "do:detail" strings.
    function step(state, event) {
        const after = Flow.next(state, event);
        return { state: after, effects: Flow.effects(state, event, after).map(e => e.do + ":" + (e.verb ?? e.run ?? e.chord ?? "")) };
    }

    function test_happy_path_needs_an_explicit_confirmation() {
        let s = step(Flow.initial(), { type: "start", change: setSession });
        compare(s.state.phase, "listening");
        compare(s.effects, ["capture:begin"]);
        verify(Flow.holdsKeyboard(s.state));
        compare(Flow.next(s.state, { type: "chord", chord: "SUPER + X" }).phase, "listening",
                "no chord before Hyprland holds the binds");
        s = step(s.state, { type: "begun", ok: true });
        compare(s.effects, ["countdown:true"]);
        let state = Flow.next(s.state, { type: "held", held: ["SUPER"] });
        compare(state.held, ["SUPER"]);
        s = step(state, { type: "chord", chord: "SUPER + ALT + I" });
        compare(s.state.phase, "recovering", "the submap is left before review");
        compare(s.effects, ["countdown:false", "capture:end"]);
        verify(!Flow.holdsKeyboard(s.state) && Flow.busy(s.state));
        s = step(s.state, { type: "released", ok: true });
        compare(s.state.phase, "review");
        compare(s.effects, ["preview:SUPER + ALT + I"]);
        compare(Flow.next(s.state, { type: "confirm" }).phase, "review", "nothing to confirm before the preview");
        state = Flow.next(s.state, { type: "previewed", preview: valid });
        compare(state.after, "SUPER + ALT + I");
        s = step(state, { type: "confirm" });
        compare(s.state.phase, "applying");
        compare(Flow.effects(state, { type: "confirm" }, s.state)[0],
                { do: "apply", version: "v1", args: ["set", "var:kbSession:0", "SUPER + ALT + I"] });
        compare(Flow.next(s.state, { type: "start", change: setSession }).phase, "applying", "no new capture while applying");
        compare(Flow.next(s.state, { type: "applied", ok: true, message: "Guardado" }).phase, "verified");
    }

    function test_a_refused_begin_fails_and_leaves_the_submap() {
        const listening = run([{ type: "start", change: setSession }]);
        const s = step(listening, { type: "begun", ok: false, message: "recarga Hyprland" });
        compare(s.state.phase, "failed");
        compare(s.state.message, "recarga Hyprland");
        compare(s.effects, ["capture:end"]);
    }

    function test_a_begin_that_never_answers_fails_like_a_refusal() {
        // The surface's watchdog sends begun(ok=false); a late real answer is ignored.
        const failed = Flow.next(run([{ type: "start", change: setSession }]), { type: "begun", ok: false, message: "sin respuesta" });
        compare(failed.phase, "failed");
        compare(Flow.next(failed, { type: "begun", ok: true }).phase, "failed");
    }

    function test_a_late_begin_answer_starts_nothing() {
        const recovering = run([{ type: "start", change: setSession }, { type: "cancel" }]);
        const s = step(recovering, { type: "begun", ok: true });
        compare(s.state.phase, "recovering");
        compare(s.effects, [], "no countdown for a capture already cancelled");
    }

    function test_conflict_can_be_repeated_or_cancelled() {
        const conflict = run([{ type: "start", change: setSession }, { type: "begun", ok: true },
                              { type: "chord", chord: "SUPER + O" }, { type: "released", ok: true },
                              { type: "previewed", preview: { valid: false, conflict: true, problem: "ya es «Spotify»" } }]);
        compare(conflict.phase, "conflict");
        compare(conflict.message, "ya es «Spotify»");
        compare(Flow.next(conflict, { type: "confirm" }).phase, "conflict", "a refused chord cannot be applied");
        compare(Flow.next(conflict, { type: "start", change: setSession }).phase, "listening");
        compare(Flow.next(conflict, { type: "cancel" }).phase, "cancelled");
    }

    function test_cancel_timeout_and_close_release_the_keyboard_first() {
        for (const type of ["cancel", "timeout", "closed"]) {
            let state = run([{ type: "start", change: setSession }, { type: "begun", ok: true }, { type: type, message: type }]);
            compare(state.phase, "recovering", type);
            verify(!Flow.holdsKeyboard(state));
            state = Flow.next(state, { type: "released", ok: true });
            compare(state.phase, "cancelled", type);
            compare(state.message, type);
        }
    }

    function test_a_failed_release_is_reported() {
        const state = run([{ type: "start", change: setSession }, { type: "cancel" },
                           { type: "released", ok: false, message: "Hyprland sigue en modo captura" }]);
        compare(state.phase, "failed");
        compare(state.message, "Hyprland sigue en modo captura");
    }

    function test_stale_and_failed_applies() {
        const ready = run([{ type: "propose", chord: "SUPER + ALT + I", change: setSession },
                           { type: "previewed", preview: valid }, { type: "confirm" }]);
        compare(Flow.next(ready, { type: "applied", ok: false, stale: true, message: "cambió" }).phase, "conflict");
        const failed = Flow.next(ready, { type: "applied", ok: false, message: "Hyprland no pudo recargar" });
        compare(failed.phase, "failed");
        compare(Flow.next(failed, { type: "reset" }).phase, "idle");
    }

    function test_events_out_of_order_change_nothing() {
        const idle = Flow.initial();
        for (const type of ["begun", "held", "chord", "released", "previewed", "confirm", "applied", "cancel"])
            compare(Flow.next(idle, { type: type, chord: "X", held: [], ok: true, preview: valid }).phase, "idle", type);
        compare(Flow.next(idle, { type: "start" }).phase, "idle", "a capture always says what it changes");
        const listening = run([{ type: "start", change: setSession }]);
        compare(Flow.next(listening, { type: "reset" }).phase, "listening", "reset never abandons a held keyboard");
        compare(Flow.next(listening, { type: "changed", ok: true }).phase, "listening");
    }

    function test_every_proposal_is_previewed() {
        let s = step(Flow.initial(), { type: "propose", chord: "XF86Calculator", change: addCalc });
        compare(s.state.phase, "review");
        compare(s.effects, ["preview:XF86Calculator"]);
        verify(!Flow.holdsKeyboard(s.state));
        const reviewed = Flow.next(s.state, { type: "previewed", preview: { valid: true, after: "XF86Calculator", version: "v1" } });
        // A second application for the same key: a new preview, the old one is gone.
        const other = { kind: "add-app", app: { id: "other", name: "Other", execString: "other" } };
        s = step(reviewed, { type: "propose", chord: "XF86Calculator", change: other });
        compare(s.effects, ["preview:XF86Calculator"]);
        compare(s.state.preview, null);
        compare(s.state.change, other);
        compare(Flow.effects(reviewed, { type: "propose", chord: "XF86Calculator", change: other }, s.state)[0].args,
                ["add-app", "XF86Calculator"]);
        compare(Flow.writeArgs(other, "XF86Calculator"), ["add-app", "other", "Other", "other", "XF86Calculator"]);
        compare(Flow.next(s.state, { type: "confirm" }).phase, "review", "the new choice needs its own preview");
        compare(Flow.next(run([{ type: "start", change: setSession }]), { type: "propose", chord: "X", change: addCalc }).phase,
                "listening", "no proposal while recording");
    }

    function test_buttons_report_through_the_flow() {
        compare(Flow.next(Flow.initial(), { type: "changed", ok: true, message: "Restaurado" }).phase, "verified");
        compare(Flow.next(Flow.initial(), { type: "changed", ok: false, message: "No" }).message, "No");
    }
}
