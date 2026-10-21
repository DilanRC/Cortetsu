import QtQuick
import QtTest
import "../../../modules"
import "../../../modules/SurfaceRegistry.js" as Surfaces
import "../../../modules/OverlayPolicy.js" as OverlayPolicy
import "../../../modules/CortetsuOverlayPolicy.js" as CortetsuOverlayPolicy

// Runtime contract of the canonical surface registry: the groups, the typed
// state built on it and both exclusion policies, evaluated by the QML engine.
TestCase {
    name: "SurfaceRegistry"

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

    // Records every write the policy sends through the typed API.
    QtObject {
        id: spy
        property var writes: []
        property bool launcher: true
        property bool overview: true
        function setFlag(flag, value) { writes = writes.concat([flag + "=" + value]); return true; }
    }

    readonly property var transientPanels: ["launcher", "session", "dashboard", "utilities", "settings", "sidebar"]
    readonly property var retainedSurfaces: ["overview", "calendar", "clipboard", "hardware", "displayManager", "wallpaperManager", "keyboards"]

    function init() {
        for (const state of [screenA, screenB])
            for (const flag of Surfaces.names)
                state[flag] = false;
        spy.writes = [];
    }

    function openFlags(state) {
        return Surfaces.names.filter(flag => state[flag]);
    }

    function test_inventory_is_complete_and_unique() {
        compare(Surfaces.names.length, 15);
        compare(new Set(Surfaces.names).size, Surfaces.names.length);
        compare(Surfaces.retained.slice().sort(), retainedSurfaces.slice().sort());
        compare(Surfaces.transient.slice().sort(), transientPanels.concat(["osd"]).sort());
        compare(Surfaces.exclusive.slice().sort(), transientPanels.concat(retainedSurfaces).sort());
        compare(Surfaces.keyboardOwners.slice().sort(), ["launcher", "session"].concat(retainedSurfaces).sort());
        compare(Surfaces.fullscreenGuarded.slice().sort(), ["dashboard", "launcher", "osd", "session", "settings", "sidebar", "utilities"]);
        verify(Surfaces.competingWithWallpaper.indexOf("wallpaperManager") < 0);
        compare(Surfaces.competingWithWallpaper.length, Surfaces.exclusive.length - 1);
        for (const flag of Surfaces.names)
            verify(screenA[flag] !== undefined, `ScreenState fixture lacks ${flag}`);
    }

    function test_registry_is_frozen() {
        verify(Object.isFrozen(Surfaces.surfaces));
        verify(Object.isFrozen(Surfaces.retained));
        verify(Object.isFrozen(Surfaces.surfaces[0]));
    }

    function test_unknown_names_are_rejected() {
        for (const bogus of ["", "bogus", "Overview", "retainedOverlayOpen", "requiresFullInputMask", "dashboardTab"]) {
            verify(!Surfaces.isKnown(bogus), bogus);
            verify(!screenA.cortetsuState.setFlag(bogus, true), bogus);
            verify(!screenA.cortetsuState.setRetained(bogus, true), bogus);
            verify(!OverlayPolicy.setFlag(screenA, bogus, true), bogus);
        }
        verify(!screenA.cortetsuState.setRetained("launcher", true));
        verify(!screenA.cortetsuState.setFlag("bar", true));
        compare(openFlags(screenA), []);
    }

    function test_setflag_routes_by_kind() {
        verify(screenA.cortetsuState.setFlag("hardware", true));
        verify(screenA.cortetsuState.setFlag("osd", true));
        verify(screenA.cortetsuState.setFlag("launcher", true));
        compare(openFlags(screenA).sort(), ["hardware", "launcher", "osd"]);
        compare(openFlags(screenB), []);
    }

    function test_derived_flags_follow_the_registry() {
        const typed = screenA.cortetsuState;
        for (const flag of retainedSurfaces) {
            screenA[flag] = true;
            verify(typed[flag], flag);
            verify(typed.retainedOverlayOpen && typed.requiresFullInputMask, flag);
            verify(typed.requiresOverlayLayer && typed.requiresWindowKeyboardFocus, flag);
            screenA[flag] = false;
            verify(!typed.retainedOverlayOpen && !typed.requiresWindowKeyboardFocus, flag);
        }
        for (const flag of ["launcher", "session"]) {
            screenA[flag] = true;
            verify(typed.requiresWindowKeyboardFocus && typed.requiresOverlayLayer, flag);
            verify(!typed.requiresFullInputMask && !typed.retainedOverlayOpen, flag);
            screenA[flag] = false;
        }
        // Parity with F0: these never claimed the drawer window's keyboard.
        for (const flag of ["dashboard", "utilities", "settings", "sidebar", "osd", "bar"]) {
            screenA[flag] = true;
            verify(!typed.requiresWindowKeyboardFocus && !typed.requiresFullInputMask, flag);
            screenA[flag] = false;
        }
    }

    function test_close_other_panels_keeps_osd_and_bar() {
        for (const flag of Surfaces.names)
            screenA[flag] = true;
        OverlayPolicy.closeOtherPanels(screenA.cortetsuState);
        compare(openFlags(screenA).sort(), ["bar", "osd"]);
    }

    function test_wallpaper_exclusion_is_bidirectional() {
        for (const flag of Surfaces.exclusive)
            screenA[flag] = true;
        verify(OverlayPolicy.hasCompetingPanel(screenA));
        verify(OverlayPolicy.hasCompetingPanel(screenA.cortetsuState));
        OverlayPolicy.closeForWallpaper(screenA);
        compare(openFlags(screenA), ["wallpaperManager"]);
        verify(!OverlayPolicy.hasCompetingPanel(screenA));
        screenA.launcher = true;
        verify(OverlayPolicy.hasCompetingPanel(screenA.cortetsuState));
        OverlayPolicy.closeOtherPanels(screenA);
        compare(openFlags(screenA), []);
    }

    function test_policy_writes_go_through_setflag() {
        OverlayPolicy.closeOtherPanels(spy);
        compare(spy.writes, Surfaces.exclusive.map(flag => flag + "=false"));
        verify(spy.launcher && spy.overview, "the policy wrote around setFlag");
        spy.writes = [];
        CortetsuOverlayPolicy.closeExclusiveEverywhere([{ cortetsuState: spy }]);
        compare(spy.writes, Surfaces.exclusive.map(flag => flag + "=false"));
        spy.writes = [];
        CortetsuOverlayPolicy.open([{ cortetsuState: spy }], { cortetsuState: spy }, "hardware");
        compare(spy.writes, Surfaces.exclusive.map(flag => flag + "=false").concat(["hardware=true"]));
    }

    function test_open_exclusive_is_idempotent() {
        screenA.launcher = true;
        screenA.hardware = true;
        screenA.osd = true;
        verify(CortetsuOverlayPolicy.open([screenA], screenA, "calendar"));
        compare(openFlags(screenA).sort(), ["calendar", "osd"]);
        verify(CortetsuOverlayPolicy.open([screenA], screenA, "calendar"));
        compare(openFlags(screenA).sort(), ["calendar", "osd"]);
        verify(!CortetsuOverlayPolicy.open([screenA], screenA, "bar"));
        verify(!CortetsuOverlayPolicy.open([screenA], screenA, "bogus"));
        compare(openFlags(screenA).sort(), ["calendar", "osd"]);
    }

    function test_close_and_reopen_cycles_leave_nothing_retained() {
        for (let cycle = 0; cycle < 40; ++cycle) {
            for (const flag of retainedSurfaces) {
                verify(CortetsuOverlayPolicy.open([screenA, screenB], screenA, flag));
                compare(openFlags(screenA), [flag]);
                verify(screenA.cortetsuState.retainedOverlayOpen);
            }
            screenA.cortetsuState.closeRetainedOverlays();
            verify(!screenA.cortetsuState.retainedOverlayOpen);
        }
        compare(openFlags(screenA), []);
        compare(openFlags(screenB), []);
    }

    function test_close_other_retained_and_except() {
        for (const flag of retainedSurfaces)
            screenA[flag] = true;
        screenA.launcher = true;
        screenA.cortetsuState.closeRetainedOverlaysExcept("clipboard");
        compare(openFlags(screenA).sort(), ["clipboard", "launcher"]);
        screenA.hardware = true;
        screenA.cortetsuState.closeRetainedOverlaysExcept("hardware");
        compare(openFlags(screenA).sort(), ["hardware", "launcher"]);
    }

    // Per-screen state stays per screen: closing the retained group of one
    // screen (Escape, fullscreen) leaves the other alone. Opening goes through
    // CortetsuOverlayPolicy.open, which is exclusive across screens
    // (tst_OverlayTransitions).
    function test_screens_are_independent() {
        screenB.hardware = true;
        screenB.sidebar = true;
        screenA.overview = true;
        compare(openFlags(screenB).sort(), ["hardware", "sidebar"]);
        verify(screenB.cortetsuState.retainedOverlayOpen);
        screenA.cortetsuState.closeRetainedOverlays();
        verify(screenB.cortetsuState.hardware);
        verify(!screenA.overview);
    }

    function test_plain_objects_keep_direct_writes() {
        // Fixtures without cortetsuState (tst_Orbit) and missing flags.
        const plain = { launcher: true, hardware: true };
        OverlayPolicy.closeOtherPanels(plain);
        compare(plain, { launcher: false, hardware: false });
        verify(!OverlayPolicy.setFlag(plain, "keyboards", true));
        verify(!OverlayPolicy.setFlag(null, "launcher", true));
        verify(!OverlayPolicy.hasCompetingPanel(null));
    }
}
