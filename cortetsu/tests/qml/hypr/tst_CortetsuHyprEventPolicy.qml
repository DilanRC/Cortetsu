import QtQuick
import QtTest
import "../../../modules/CortetsuHyprEventPolicy.js" as HyprEventPolicy

TestCase {
    name: "CortetsuHyprEventPolicy"

    function test_native_title_and_focus_events_do_not_request_toplevel_refreshes() {
        for (const name of ["windowtitle", "activewindow", "windowtitlev2", "activewindowv2"]) {
            const plan = HyprEventPolicy.refreshPlan(name);
            compare(plan.refreshMonitors, false, name);
            compare(plan.refreshWorkspaces, false, name);
            compare(plan.refreshToplevels, false, name);
        }
    }

    function test_window_inventory_changes_refresh_toplevels_and_workspaces() {
        for (const name of ["openwindow", "closewindow", "movewindow"]) {
            const plan = HyprEventPolicy.refreshPlan(name);
            compare(plan.refreshMonitors, false, name);
            compare(plan.refreshWorkspaces, true, name);
            compare(plan.refreshToplevels, true, name);
        }
    }

    function test_workspace_and_focus_legacy_events_refresh_compositor_models() {
        for (const name of ["workspace", "moveworkspace", "activespecial", "focusedmon"]) {
            const plan = HyprEventPolicy.refreshPlan(name);
            compare(plan.refreshMonitors, true, name);
            compare(plan.refreshWorkspaces, true, name);
            compare(plan.refreshToplevels, false, name);
        }
    }

    function test_monitor_legacy_events_refresh_only_monitors() {
        for (const name of ["monitoradded", "monitorremoved"]) {
            const plan = HyprEventPolicy.refreshPlan(name);
            compare(plan.refreshMonitors, true, name);
            compare(plan.refreshWorkspaces, false, name);
            compare(plan.refreshToplevels, false, name);
        }
    }

    function test_fullscreen_pin_float_minimize_and_groups_refresh_toplevels() {
        for (const name of ["fullscreen", "pin", "changefloatingmode", "minimize", "windowgroup"]) {
            const plan = HyprEventPolicy.refreshPlan(name);
            compare(plan.refreshToplevels, true, name);
        }
    }

    function test_unrelated_or_invalid_events_do_not_trigger_queries() {
        for (const name of ["activelayout", "configreloaded", "", null, 7]) {
            const plan = HyprEventPolicy.refreshPlan(name);
            compare(plan.refreshMonitors, false);
            compare(plan.refreshWorkspaces, false);
            compare(plan.refreshToplevels, false);
        }
    }
}
