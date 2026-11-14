import QtQuick
import QtTest
import "../../../modules"
import "../../../theme"
import "../../../theme/ThemeProfiles.js" as ThemeProfiles

// The Hub's islands: their states (rest, hover, keyboard focus inside,
// engaged by an open popout), reduced motion, the theme's elevation and the
// App Rail's window preview requests. The whole view (it loads Quickshell)
// is in scripts/features/test-cortetsu-hub-islands-runtime.py.
TestCase {
    id: testCase
    name: "HubIslands"
    when: windowShown
    visible: true
    width: 1280
    height: 400

    property var dockItems: [
        { key: "files", title: "Files", active: false, pinned: true, running: true, windowCount: 2, iconSource: "" },
        { key: "notes", title: "Notes", active: false, pinned: true, running: false, windowCount: 0, iconSource: "" }
    ]

    Component {
        id: railComponent
        CortetsuAppRail {
            items: testCase.dockItems
            maxWidth: 500
        }
    }

    SignalSpy { id: hoverSpy; signalName: "previewHoverRequested" }
    SignalSpy { id: hoverEndSpy; signalName: "previewHoverEnded" }
    SignalSpy { id: menuSpy; signalName: "previewRequested" }
    SignalSpy { id: cycleSpy; signalName: "cycleRequested" }

    function find(item, test) {
        if (test(item))
            return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) {
            const hit = find(kids[i], test);
            if (hit)
                return hit;
        }
        return null;
    }

    function islandOf(segment) {
        return find(segment, c => c.engaged !== undefined && c.segment === segment);
    }

    function sameColour(a, b) {
        return Math.abs(a.r - b.r) < 0.01 && Math.abs(a.g - b.g) < 0.01
            && Math.abs(a.b - b.b) < 0.01 && Math.abs(a.a - b.a) < 0.01;
    }

    function cleanup() {
        CortetsuDesign.reducedMotion = false;
        CortetsuDesign.themeTokens = ThemeProfiles.tokens("ink");
    }

    function test_engaged_island_turns_indigo() {
        const rail = createTemporaryObject(railComponent, testCase);
        const island = islandOf(rail);
        verify(island !== null);
        CortetsuDesign.reducedMotion = true;
        verify(!island.engaged);
        rail.engaged = true;
        verify(island.engaged);
        verify(sameColour(island.border.color, Qt.alpha(CortetsuDesign.colorIndigo, 0.62)), `${island.border.color}`);
        rail.engaged = false;
        verify(!sameColour(island.border.color, Qt.alpha(CortetsuDesign.colorIndigo, 0.62)));
    }

    function test_reduced_motion_is_instant_and_motion_is_not() {
        const rail = createTemporaryObject(railComponent, testCase);
        const island = islandOf(rail);
        const target = Qt.alpha(CortetsuDesign.colorIndigo, 0.62);
        CortetsuDesign.reducedMotion = false;
        rail.engaged = true;
        verify(!sameColour(island.border.color, target), "with motion the edge eases towards indigo");
        tryVerify(() => sameColour(island.border.color, target), 1000);
        rail.engaged = false;
        CortetsuDesign.reducedMotion = true;
        wait(0);
        rail.engaged = true;
        verify(sameColour(island.border.color, target), "reduced motion: at once");
    }

    function test_hover_and_keyboard_focus_raise_the_edge() {
        CortetsuDesign.reducedMotion = true;
        const rail = createTemporaryObject(railComponent, testCase);
        const island = islandOf(rail);
        // A copy: a colour read from a property is a live reference in Qt 6.
        const c = island.border.color;
        const rest = Qt.rgba(c.r, c.g, c.b, c.a);
        mouseMove(rail, rail.width / 2, rail.height / 2);
        tryVerify(() => island.hovered, 1000);
        verify(!sameColour(island.border.color, rest), "hover lifts the edge");
        mouseMove(testCase, testCase.width - 5, testCase.height - 5);
        tryVerify(() => !island.hovered, 1000);
        const icon = find(rail, c => c.objectName === "dock-files");
        icon.forceActiveFocus();
        tryVerify(() => island.focused, 1000);
        verify(sameColour(island.border.color, Qt.alpha(CortetsuDesign.colorWashi, 0.42)), "focus inside draws the edge");
    }

    function test_elevation_follows_the_theme() {
        const rail = createTemporaryObject(railComponent, testCase);
        const island = islandOf(rail);
        const shadows = () => island.children.filter(c => c.z < 0 && c.visible).length;
        CortetsuDesign.themeTokens = ThemeProfiles.tokens("ink");
        compare(CortetsuDesign.materialShadowAlpha, 0);
        compare(shadows(), 0);
        CortetsuDesign.themeTokens = ThemeProfiles.tokens("washi");
        verify(CortetsuDesign.materialShadowAlpha > 0);
        compare(shadows(), 2);
        CortetsuDesign.themeTokens = ThemeProfiles.tokens("kurogane");
        compare(shadows(), CortetsuDesign.materialShadowAlpha > 0 ? 2 : 0);
    }

    function test_rail_asks_for_a_running_apps_preview() {
        const rail = createTemporaryObject(railComponent, testCase);
        hoverSpy.target = rail; hoverEndSpy.target = rail; menuSpy.target = rail; cycleSpy.target = rail;
        hoverSpy.clear(); hoverEndSpy.clear(); menuSpy.clear(); cycleSpy.clear();
        const files = rail.buttonFor("files");
        const notes = rail.buttonFor("notes");
        verify(files !== null && notes !== null);
        compare(rail.buttonFor("nope"), null);
        mouseMove(files, files.width / 2, files.height / 2);
        tryCompare(hoverSpy, "count", 1);
        compare(hoverSpy.signalArguments[0][0], "files");
        // The anchor is the icon's centre along the rail.
        const centre = files.mapToItem(rail, files.width / 2, 0).x;
        compare(hoverSpy.signalArguments[0][1], centre);
        mouseMove(notes, notes.width / 2, notes.height / 2);
        tryVerify(() => hoverEndSpy.count >= 1, 1000);
        compare(hoverSpy.count, 1, "a pinned app that is not running has no windows to show");
        files.forceActiveFocus();
        keyClick(Qt.Key_Menu);
        compare(menuSpy.count, 1);
        notes.forceActiveFocus();
        keyClick(Qt.Key_Menu);
        compare(menuSpy.count, 1);
    }

    function test_open_preview_takes_the_keys_typed_on_the_icon() {
        const rail = createTemporaryObject(railComponent, testCase);
        cycleSpy.target = rail;
        cycleSpy.clear();
        const keys = [];
        rail.previewKeyHandler = (key, modifiers) => { keys.push(key); return true; };
        const files = rail.buttonFor("files");
        files.forceActiveFocus();
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Escape);
        compare(keys, [Qt.Key_Right, Qt.Key_Return, Qt.Key_Escape]);
        compare(cycleSpy.count, 0, "Right went to the preview, not to cycling windows");
        rail.previewKeyHandler = () => false;
        keyClick(Qt.Key_Right);
        compare(cycleSpy.count, 1, "without a preview Right cycles the app's windows");
    }
}
