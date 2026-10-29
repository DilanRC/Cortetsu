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
                    ownsKeyboard: true, open: true, openCause: "hover_preview" },
                { name: "overview", kind: "retained", exclusive: true,
                    ownsKeyboard: true, open: false }
            ], focusGrab: { requested: false, active: false,
                windows: ["drawers", "bottom_hub"] },
            bottomHub: { shown: false, popup: "", open: false, closing: false,
                keyboardFocusPolicy: "none" },
            transitions: [{ surface: "drawers.fullscreen", active: true, progress: 0.5 }] }],
            focus: { monitor: "eDP-1", workspace: { id: 2, name: "2" },
                window: { address: "0x1234", class: "kitty", monitor: "eDP-1", title: "probe" },
                keyboardOwner: { state: "requested_unobserved", observable: false,
                    surface: null, candidates: ["eDP-1:launcher"] } },
            fullscreen: { focused: false, windows: [] },
            hyprlandQueries: { clientSnapshots: { count: 4, totalMs: 12, maxMs: 5 },
                toplevelRefreshCalls: 7, windowTitleRefreshCalls: 2 },
            eventStream: { quickshellReconnectSupported: false, quickshellStatusObservable: false, lost: true,
                cortetsuObserverReconnectSupported: true }
        });

        compare(snapshot.schema_version, 2);
        compare(snapshot.observed_at, "2026-10-24T16:00:00.000Z");
        compare(snapshot.monitors.length, 1);
        compare(snapshot.monitors[0].name, "eDP-1");
        compare(snapshot.focus.monitor, "eDP-1");
        compare(snapshot.focus.window.monitor, "eDP-1");
        compare(snapshot.focus.keyboard_owner.observable, false);
        compare(snapshot.focus.keyboard_owner.state, "requested_unobserved");
        compare(snapshot.surfaces[0].activation_cause, "hover_preview");
        compare(snapshot.focus_grabs[0].active, false);
        compare(snapshot.focus_grabs[0].windows, ["drawers", "bottom_hub"]);
        compare(snapshot.focus_grabs[0].cleared_at_epoch_ms, 0);
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
        compare(snapshot.hyprland_event_stream.lost, true);
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
        compare(snapshot.schema_version, 2);
        compare(snapshot.monitors, []);
        compare(snapshot.surfaces, []);
        compare(snapshot.open_states, []);
        compare(snapshot.focus_grabs, []);
        compare(snapshot.bottom_hub, []);
        compare(snapshot.overlays, []);
        compare(snapshot.transitions, []);
        compare(snapshot.conflicts, []);
        compare(snapshot.fullscreen, { focused: false, windows: [] });
        compare(snapshot.focus.keyboard_owner.state, "unobservable");
        compare(snapshot.hyprland_queries.client_snapshots, { count: 0, total_ms: 0, max_ms: 0 });
        compare(snapshot.hyprland_queries.toplevel_refresh_calls, 0);
        compare(snapshot.hyprland_queries.windowtitle_refresh_calls, 0);
        compare(snapshot.hyprland_event_stream.quickshell_reconnect_supported, false);
        compare(snapshot.hyprland_event_stream.lost, false);
        verify(JSON.parse(JSON.stringify(snapshot)).schema_version === 2);
    }

    function test_exclusive_layer_request_is_not_misreported_as_the_focused_toplevel() {
        const owner = ShellInspect.resolveKeyboardOwner({
            focusGrabs: [],
            hosts: [
                { monitor: "eDP-1", surface: "drawers", policy: "on_demand", active: false },
                { monitor: "eDP-1", surface: "retained_surfaces", policy: "exclusive", active: false },
                { monitor: "eDP-1", surface: "bottom_hub", policy: "on_demand", active: false }
            ],
            focusedToplevel: { monitor: "eDP-1" }
        });

        compare(owner.state, "requested_unobserved");
        compare(owner.observable, false);
        compare(owner.surface, "retained_surfaces");
        compare(owner.source, "WlrLayershell.keyboardFocus");
        compare(owner.policy, "exclusive");
        compare(owner.candidates.length, 3);
    }

    function test_focus_grab_is_observed_and_coalesces_its_allowed_windows() {
        const owner = ShellInspect.resolveKeyboardOwner({
            focusGrabs: [{ monitor: "HDMI-A-1", active: true }],
            hosts: [
                { monitor: "HDMI-A-1", surface: "drawers", policy: "on_demand", active: true },
                { monitor: "HDMI-A-1", surface: "bottom_hub", policy: "on_demand", active: true }
            ]
        });

        compare(owner.state, "observed");
        compare(owner.observable, true);
        compare(owner.surface, "drawers.focus_grab");
        compare(owner.source, "HyprlandFocusGrab.active");
    }

    function test_focused_toplevel_uses_its_monitor_not_the_pointer_monitor() {
        const owner = ShellInspect.resolveKeyboardOwner({
            hosts: [],
            pointerMonitor: "eDP-1",
            focusedToplevel: { monitor: "HDMI-A-1" }
        });

        compare(owner.state, "observed");
        compare(owner.surface, "toplevel");
        compare(owner.monitor, "HDMI-A-1");
    }

    function test_window_active_confirms_a_layer_owner() {
        const owner = ShellInspect.resolveKeyboardOwner({
            hosts: [{ monitor: "eDP-1", surface: "launcher", policy: "exclusive", active: true }]
        });

        compare(owner.state, "observed");
        compare(owner.surface, "launcher");
        compare(owner.source, "QQuickWindow.active");
    }

    function test_focused_toplevel_owns_keyboard_when_only_ondemand_layers_are_pending() {
        const owner = ShellInspect.resolveKeyboardOwner({
            hosts: [{ monitor: "eDP-1", surface: "bottom_hub", policy: "on_demand", active: false }],
            focusedToplevel: { monitor: "eDP-1" }
        });

        compare(owner.state, "observed");
        compare(owner.surface, "toplevel");
        compare(owner.source, "Hyprland.focusedToplevel");
    }

    function test_ondemand_layer_is_owner_only_when_active_is_observed() {
        const pending = ShellInspect.resolveKeyboardOwner({
            hosts: [{ monitor: "eDP-1", surface: "retained_surfaces", policy: "on_demand", active: false }]
        });
        compare(pending.state, "requested_unobserved");
        compare(pending.observable, false);
        compare(pending.policy, "on_demand");

        const active = ShellInspect.resolveKeyboardOwner({
            hosts: [{ monitor: "eDP-1", surface: "retained_surfaces", policy: "on_demand", active: true }]
        });
        compare(active.state, "observed");
        compare(active.observable, true);
        compare(active.surface, "retained_surfaces");
        compare(active.source, "QQuickWindow.active");
    }

    function test_ambiguous_owner_keeps_requested_and_observed_candidates_separate() {
        const owner = ShellInspect.resolveKeyboardOwner({
            hosts: [
                { monitor: "eDP-1", surface: "drawers", policy: "on_demand", active: true },
                { monitor: "HDMI-A-1", surface: "retained_surfaces", policy: "on_demand", active: true }
            ]
        });

        compare(owner.state, "ambiguous");
        compare(owner.candidates, ["eDP-1:drawers:on_demand", "HDMI-A-1:retained_surfaces:on_demand"]);
        compare(owner.observed_candidates, [
            { monitor: "eDP-1", surface: "drawers", policy: "on_demand", source: "QQuickWindow.active" },
            { monitor: "HDMI-A-1", surface: "retained_surfaces", policy: "on_demand", source: "QQuickWindow.active" }
        ]);
    }
}
