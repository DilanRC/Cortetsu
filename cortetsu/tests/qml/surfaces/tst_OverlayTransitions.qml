import QtQuick
import QtTest
import "../../../modules"
import "../../../modules/SurfaceRegistry.js" as Surfaces
import "../../../modules/CortetsuOverlayPolicy.js" as Policy

// Multi-screen transitions of CortetsuOverlayPolicy: the functions every
// shortcut, IPC handler, Bottom Hub button, Settings link and controller calls.
// O-1 (a retained surface opened on another screen left the previous one open)
// and O-2 (`drawers toggle sidebar` stacked over Hardware) fail here against
// the per-screen rules they replaced.
TestCase {
    name: "OverlayTransitions"

    component LegacyState: QtObject {
        id: legacy
        property bool bar
        property bool osd
        property bool session
        property bool launcher
        property bool dashboard
        property bool utilities
        property bool settings
        property bool sidebar
        property bool overview
        property bool calendar
        property bool clipboard
        property bool hardware
        property bool displayManager
        property bool wallpaperManager
        property bool keyboards
        readonly property CortetsuScreenState cortetsuState: CortetsuScreenState { legacyState: legacy }
    }

    LegacyState { id: screenA }
    LegacyState { id: screenB }

    readonly property var states: [screenA, screenB]
    readonly property var transientPanels: ["launcher", "session", "dashboard", "utilities", "settings", "sidebar"]

    function init() {
        for (const state of states)
            for (const flag of Surfaces.names)
                state[flag] = false;
    }

    function openFlags() {
        return states.map(state => Surfaces.names.filter(flag => state[flag]));
    }

    // The controllers pass typed states (cortetsuState), Shortcuts and Bottom
    // Hub the legacy ones: both must give the same result.
    function test_retained_is_exclusive_across_screens_data() {
        const rows = [];
        for (const first of Surfaces.retained)
            for (const second of Surfaces.retained)
                if (first !== second)
                    for (const typed of [false, true])
                        rows.push({ tag: `${first} then ${second}${typed ? " (typed)" : ""}`, first, second, typed });
        return rows;
    }

    function test_retained_is_exclusive_across_screens(data) {
        const all = data.typed ? states.map(state => state.cortetsuState) : states;
        verify(Policy.open(all, all[0], data.first));
        verify(Policy.open(all, all[1], data.second));
        compare(openFlags(), [[], [data.second]]);
    }

    function test_retained_moves_instead_of_doubling() {
        verify(Policy.open(states, screenA, "calendar"));
        verify(Policy.open(states, screenB, "calendar"));
        compare(openFlags(), [[], ["calendar"]]);
    }

    function test_transient_closes_retained_on_any_screen_data() {
        return transientPanels.map(panel => ({ tag: panel, panel }));
    }

    function test_transient_closes_retained_on_any_screen(data) {
        for (const [where, target] of [["same screen", screenA], ["other screen", screenB]]) {
            init();
            Policy.open(states, screenA, "hardware");
            verify(Policy.toggle(states, target, data.panel), where);
            compare(openFlags(), target === screenA ? [[data.panel], []] : [[], [data.panel]], where);
            // And back: Hardware closes the panel wherever it is.
            Policy.open(states, screenA, "hardware");
            compare(openFlags(), [["hardware"], []], where);
        }
    }

    // O-2: the IPC route (`drawers toggle sidebar`) and SUPER+N are the same call.
    function test_sidebar_over_hardware_is_one_surface() {
        Policy.open(states, screenA, "hardware");
        verify(Policy.toggleGuarded(states, screenA, "sidebar", false));
        compare(openFlags(), [["sidebar"], []]);
        verify(!Policy.toggleGuarded(states, screenA, "sidebar", false));
        compare(openFlags(), [[], []]);
    }

    // O-3 at the state level: the sidebar closes the Wallpaper Manager and stays.
    function test_sidebar_closes_the_wallpaper_manager() {
        Policy.open(states, screenA, "wallpaperManager");
        Policy.toggle(states, screenA, "sidebar");
        compare(openFlags(), [["sidebar"], []]);
    }

    function test_osd_and_bar_are_left_alone() {
        screenA.bar = true;
        verify(Policy.toggle(states, screenA, "osd"));
        verify(Policy.open(states, screenB, "osd"));
        Policy.open(states, screenA, "hardware");
        compare(openFlags(), [["hardware", "osd", "bar"], ["osd"]]);
        // osd toggles per screen and never closes an exclusive surface.
        verify(!Policy.toggle(states, screenA, "osd"));
        verify(screenA.hardware && screenB.osd && !screenA.osd);
    }

    function test_retained_toggle_closes_it_from_any_screen() {
        Policy.open(states, screenA, "hardware");
        verify(!Policy.toggle(states, screenB, "hardware"));
        compare(openFlags(), [[], []]);
        verify(Policy.toggle(states, screenB, "hardware"));
        compare(openFlags(), [[], ["hardware"]]);
    }

    // Bottom Hub buttons: open on their own screen, moving the surface there.
    function test_toggle_on_moves_to_its_screen() {
        Policy.open(states, screenA, "calendar");
        verify(Policy.toggleOn(states, screenB, "calendar"));
        compare(openFlags(), [[], ["calendar"]]);
        verify(!Policy.toggleOn(states, screenB, "calendar"));
        compare(openFlags(), [[], []]);
    }

    function test_transient_toggle_is_per_screen() {
        verify(Policy.toggle(states, screenA, "dashboard"));
        verify(Policy.toggle(states, screenB, "dashboard"));
        compare(openFlags(), [[], ["dashboard"]]);
        verify(!Policy.toggle(states, screenB, "dashboard"));
        compare(openFlags(), [[], []]);
    }

    function test_fullscreen_blocks_opening_guarded_surfaces_only() {
        for (const flag of Surfaces.fullscreenGuarded) {
            init();
            verify(!Policy.toggleGuarded(states, screenA, flag, true), flag);
            compare(openFlags(), [[], []], flag);
            // Closing is never blocked (SUPER+N could not close the sidebar before).
            screenA[flag] = true;
            verify(!Policy.toggleGuarded(states, screenA, flag, true), flag);
            verify(!screenA[flag], flag);
        }
        for (const flag of Surfaces.retained) {
            init();
            verify(Policy.toggleGuarded(states, screenA, flag, true), flag);
        }
    }

    function test_rejects_unknown_and_chrome_flags() {
        for (const flag of ["", "bogus", "bar", "retainedOverlayOpen"]) {
            verify(!Policy.open(states, screenA, flag), flag);
            verify(!Policy.toggle(states, screenA, flag), flag);
            verify(!Policy.close(states, flag), flag);
        }
        verify(!Policy.open(states, null, "hardware"));
        verify(!Policy.toggle(states, undefined, "sidebar"));
        compare(openFlags(), [[], []]);
    }

    function test_close_everywhere() {
        screenA.hardware = true;
        screenB.hardware = true;
        verify(Policy.close(states, "hardware"));
        verify(!Policy.openAnywhere(states, "hardware"));
        verify(Policy.isOpen(screenA.cortetsuState, "osd") === false);
    }

    // Every surface, both screens, opened and closed 40 times: nothing leaks.
    function test_cycles_leave_nothing_open() {
        const settable = Surfaces.names.filter(flag => Surfaces.isSettable(flag));
        for (let cycle = 0; cycle < 40; ++cycle) {
            for (const flag of settable) {
                const target = states[cycle % 2];
                verify(Policy.toggle(states, target, flag), `${flag} ${cycle}`);
                const open = [].concat(...openFlags());
                verify(open.includes(flag), flag);
                if (Surfaces.find(flag).exclusive)
                    compare(open.filter(other => Surfaces.find(other).exclusive), [flag], `${flag} ${cycle}`);
                verify(!Policy.toggle(states, target, flag), `${flag} ${cycle}`);
            }
            Policy.close(states, "osd");
            compare(openFlags(), [[], []], `cycle ${cycle}`);
        }
    }
}
