import QtQuick
import QtTest
import "../../../modules/CortetsuShellInspect.js" as ShellInspect

TestCase {
    name: "CortetsuShellInspect"

    function test_snapshot_has_versioned_sections_and_open_states() {
        const snapshot = ShellInspect.buildSnapshot({
            observedAt: "2026-10-24T16:00:00.000Z",
            monitors: [{ name: "eDP-1", width: 1920, height: 1080, scale: 1.25,
                focused: true, activeWorkspace: { id: 2, name: "2" } }],
            screens: [{ name: "eDP-1", surfaces: [
                { name: "launcher", kind: "transient", exclusive: true,
                    ownsKeyboard: true, open: true },
                { name: "overview", kind: "retained", exclusive: true,
                    ownsKeyboard: true, open: false }
            ], focusGrab: { requested: false, active: false },
            bottomHub: { shown: false, popup: "", open: false, closing: false,
                keyboardFocusPolicy: "none" },
            transitions: [{ surface: "drawers.fullscreen", active: true, progress: 0.5 }] }],
            focus: { monitor: "eDP-1", workspace: { id: 2, name: "2" },
                window: { address: "0x1234", class: "kitty", title: "probe" },
                keyboardOwner: { observable: false, surface: null, candidates: ["launcher"] } },
            fullscreen: { focused: false, windows: [] },
            hyprlandQueries: { clientSnapshots: { count: 4, totalMs: 12, maxMs: 5 },
                toplevelRefreshCalls: 7, windowTitleRefreshCalls: 2 },
            eventStream: { quickshellReconnectSupported: false, quickshellStatusObservable: false,
                cortetsuObserverReconnectSupported: true }
        });

        compare(snapshot.schema_version, 1);
        compare(snapshot.observed_at, "2026-10-24T16:00:00.000Z");
        compare(snapshot.monitors.length, 1);
        compare(snapshot.monitors[0].name, "eDP-1");
        compare(snapshot.focus.monitor, "eDP-1");
        compare(snapshot.focus.keyboard_owner.observable, false);
        compare(snapshot.focus_grabs[0].active, false);
        compare(snapshot.bottom_hub[0].shown, false);
        compare(snapshot.bottom_hub[0].keyboard_focus_policy, "none");
        compare(snapshot.fullscreen.focused, false);
        compare(snapshot.transitions,
            [{ monitor: "eDP-1", surface: "drawers.fullscreen", progress: 0.5 }]);
        compare(snapshot.hyprland_queries.client_snapshots,
            { count: 4, total_ms: 12, max_ms: 5 });
        compare(snapshot.hyprland_queries.toplevel_refresh_calls, 7);
        compare(snapshot.hyprland_queries.windowtitle_refresh_calls, 2);
        compare(snapshot.hyprland_event_stream.quickshell_reconnect_supported, false);
        compare(snapshot.hyprland_event_stream.cortetsu_observer_reconnect_supported, true);
        compare(snapshot.open_states, [{ monitor: "eDP-1", surface: "launcher" }]);
        compare(snapshot.overlays, []);
        compare(snapshot.conflicts, []);
    }

    function test_conflicts_are_reported_for_coexisting_exclusive_surfaces() {
        const snapshot = ShellInspect.buildSnapshot({
            observedAt: "2026-10-24T16:00:00.000Z",
            monitors: [{ name: "eDP-1", width: 1920, height: 1080 }],
            screens: [{ name: "eDP-1", surfaces: [
                { name: "launcher", kind: "transient", exclusive: true,
                    ownsKeyboard: true, open: true },
                { name: "calendar", kind: "retained", exclusive: true,
                    ownsKeyboard: true, open: true }
            ], focusGrab: { requested: false, active: false },
            bottomHub: { shown: false, popup: "", open: false, closing: false },
            transitions: [] }],
            focus: { monitor: "eDP-1", keyboardOwner: { observable: false, surface: null, candidates: [] } },
            fullscreen: { focused: true, windows: ["0xabcd"] }
        });

        compare(snapshot.open_states.length, 2);
        compare(snapshot.overlays, [{ monitor: "eDP-1", surface: "calendar" }]);
        compare(snapshot.conflicts.length, 1);
        compare(snapshot.conflicts[0].surfaces, ["launcher", "calendar"]);
        compare(snapshot.fullscreen.windows, ["0xabcd"]);
    }

    function test_exclusive_surfaces_on_different_monitors_are_not_conflicts() {
        const snapshot = ShellInspect.buildSnapshot({
            screens: [
                { name: "eDP-1", surfaces: [
                    { name: "launcher", kind: "transient", exclusive: true,
                        ownsKeyboard: true, open: true }
                ] },
                { name: "HDMI-A-1", surfaces: [
                    { name: "calendar", kind: "retained", exclusive: true,
                        ownsKeyboard: true, open: true }
                ] }
            ]
        });

        compare(snapshot.open_states.length, 2);
        compare(snapshot.conflicts, []);
    }

    function test_empty_snapshot_keeps_a_stable_json_shape() {
        const snapshot = ShellInspect.buildSnapshot({});
        compare(snapshot.schema_version, 1);
        compare(snapshot.monitors, []);
        compare(snapshot.surfaces, []);
        compare(snapshot.open_states, []);
        compare(snapshot.focus_grabs, []);
        compare(snapshot.bottom_hub, []);
        compare(snapshot.overlays, []);
        compare(snapshot.transitions, []);
        compare(snapshot.conflicts, []);
        compare(snapshot.fullscreen, { focused: false, windows: [] });
        compare(snapshot.hyprland_queries.client_snapshots, { count: 0, total_ms: 0, max_ms: 0 });
        compare(snapshot.hyprland_queries.toplevel_refresh_calls, 0);
        compare(snapshot.hyprland_queries.windowtitle_refresh_calls, 0);
        compare(snapshot.hyprland_event_stream.quickshell_reconnect_supported, false);
        verify(JSON.parse(JSON.stringify(snapshot)).schema_version === 1);
    }
}
