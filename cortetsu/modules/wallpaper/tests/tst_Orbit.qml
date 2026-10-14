import QtQuick
import QtTest
import "../OrbitModel.js" as Orbit
import "../../OverlayPolicy.js" as OverlayPolicy

TestCase {
    name: "OrbitModel"
    function paths(count) {
        const result = [];
        for (let i = 0; i < count; ++i)
            result.push({path: `/walls/cat/${i}.webp`});
        return result;
    }
    function test_prefetch_is_bounded_but_larger_than_orbit() {
        compare(Orbit.prefetch(paths(300), 0, 18).length, 18);
        compare(Orbit.prefetch(paths(5), 0, 18).length, 5);
        compare(Orbit.prefetch(paths(0), 0, 18).length, 0);
        compare(Orbit.prefetch(paths(300), 299, 18)[10].path, "/walls/cat/0.webp");
    }
    function test_current_path_resolution() {
        const entries = [
            {path: "/home/dilan/Imágenes/Wallpapers/388074.jpg"},
            {path: "/walls/other.jpg"}
        ];
        compare(Orbit.resolveCurrentIndex(entries, "/home/dilan/Imágenes/Wallpapers/388074.jpg"), 0);
        compare(Orbit.resolveCurrentIndex(entries, "/home/dilan/Pictures/Wallpapers/388074.jpg"), 0);
        compare(Orbit.resolveCurrentIndex(entries, "/home/dilan/Pictures/Wallpapers/missing.jpg"), -1);
        entries.push({path: "/archive/388074.jpg"});
        compare(Orbit.resolveCurrentIndex(entries, "/home/dilan/Pictures/Wallpapers/388074.jpg"), -1);
        compare(Orbit.resolveCurrentIndex(entries, "/home/dilan/Imágenes/Wallpapers/388074.jpg"), 0);
    }
    function test_arc_wraps_a_large_collection() {
        const entries = paths(300);
        const arc = Orbit.arc(entries, 0, 5);
        compare(arc.length, 11);
        compare(arc.map(item => item.offset).join(","), "-5,-4,-3,-2,-1,0,1,2,3,4,5");
        compare(arc[0].index, 295);
        compare(arc[5].index, 0);
        compare(arc[10].entry.path, entries[5].path);
        compare(Orbit.arcSteps(0, 299, 300, 5), -1);
    }
    function test_arc_lays_a_small_collection_as_a_strip_data() {
        return [
            {tag: "empty", count: 0, anchor: -1, expected: ""},
            {tag: "one", count: 1, anchor: 0, expected: "0"},
            {tag: "two", count: 2, anchor: 1, expected: "-1,0"},
            {tag: "exact window", count: 11, anchor: 0, expected: "0,1,2,3,4,5,6,7,8,9,10"}
        ];
    }
    function test_arc_lays_a_small_collection_as_a_strip(data) {
        const arc = Orbit.arc(paths(data.count), data.anchor, 5);
        compare(arc.map(item => item.offset).join(","), data.expected);
        // Every entry appears once, so re-anchoring never moves one across.
        compare(arc.map(item => item.index).join(","), paths(data.count).map((entry, index) => index).join(","));
    }
    function test_strip_moves_do_not_wrap() {
        compare(Orbit.arcSteps(0, 7, 8, 5), 7);
        compare(Orbit.arcSteps(7, 0, 8, 5), -7);
        compare(Orbit.arcSteps(0, 7, 12, 5), -5);
    }
    function test_arc_geometry() {
        const span = Math.PI * 0.39;
        compare(Orbit.arcAngle(0, 0, 5, span), -Math.PI / 2);
        // A finished turn puts the neighbour exactly where the selection was.
        compare(Orbit.arcAngle(1, 1, 5, span), Orbit.arcAngle(0, 0, 5, span));
        compare(Orbit.arcAngle(-2, 0, 5, span), -Math.PI / 2 - 2 * span / 5);
        compare(Orbit.arcDepth(Orbit.arcAngle(0, 0, 5, span), span), 1);
        compare(Orbit.arcDepth(Orbit.arcAngle(5, 0, 5, span), span), 0);
        compare(Orbit.arcDepth(Orbit.arcAngle(-9, 0, 5, span), span), 0);
        const near = Orbit.arcDepth(Orbit.arcAngle(1, 0, 5, span), span);
        const far = Orbit.arcDepth(Orbit.arcAngle(4, 0, 5, span), span);
        verify(near < 1 && far > 0 && near > far);
        fuzzyCompare(Orbit.arcDepth(Orbit.arcAngle(-3, 0, 5, span), span), Orbit.arcDepth(Orbit.arcAngle(3, 0, 5, span), span), 1e-9);
    }
    function test_wrap_and_unicode() {
        compare(Orbit.move(0, -1, 13), 12);
        compare(Orbit.move(12, 1, 13), 0);
        const entries = [{path: "/walls/日本/星 空.webp"}, {path: "/walls/night/luna.png"}];
        compare(Orbit.filtered(entries, "日本", entry => entry.path.split("/")[2])[0].path, "/walls/日本/星 空.webp");
    }
    function test_shortest_steps() {
        compare(Orbit.shortestSteps(0, 12, 13), -1);
        compare(Orbit.shortestSteps(0, 7, 12), -5);
        compare(Orbit.shortestSteps(3, 3, 12), 0);
    }
    function test_category_counts() {
        const entries = [{kind: "loose"}, {kind: "fog"}, {kind: "night"}, {kind: "fog"}];
        const counts = Orbit.categoryCounts(entries, entry => entry.kind, "loose");
        compare(counts.map(item => `${item.name}:${item.count}`).join(","), "ALL:4,fog:2,night:1,loose:1");
        compare(Orbit.categoryCounts([], entry => entry.kind, "loose").length, 1);
    }
    function test_wheel_threshold_and_reversal() {
        let intent = Orbit.wheelIntent(0, 60, 0);
        compare(intent.direction, 0);
        compare(intent.accumulator, 60);
        intent = Orbit.wheelIntent(intent.accumulator, 60, 0);
        compare(intent.direction, -1);
        compare(intent.accumulator, 0);
        intent = Orbit.wheelIntent(30, -80, 0);
        compare(intent.direction, 0);
        compare(intent.accumulator, -80);
        intent = Orbit.wheelIntent(intent.accumulator, -70, 0);
        compare(intent.direction, 1);
        compare(intent.accumulator, -30);
    }
    function test_wheel_oversize_and_immediate_reversal() {
        let intent = Orbit.wheelIntent(0, 0, 100);
        compare(intent.direction, -1);
        compare(intent.accumulator, 20);
        verify(Math.abs(intent.accumulator) < 40);
        intent = Orbit.wheelIntent(intent.accumulator, 0, -1);
        compare(intent.direction, 0);
        compare(intent.accumulator, -1);
        intent = Orbit.wheelIntent(0, 0, -100);
        compare(intent.direction, 1);
        compare(intent.accumulator, -20);
        verify(Math.abs(intent.accumulator) < 40);
        intent = Orbit.wheelIntent(0, 360, 0);
        compare(intent.direction, -1);
        compare(intent.accumulator, 0);
        intent = Orbit.wheelIntent(0, -360, 0);
        compare(intent.direction, 1);
        compare(intent.accumulator, 0);
        intent = Orbit.wheelIntent(0, 120, 0);
        compare(intent.direction, -1);
        compare(intent.accumulator, 0);
        intent = Orbit.wheelIntent(0, 0, -40);
        compare(intent.direction, 1);
        compare(intent.accumulator, 0);
    }
    function test_overlay_policy_bidirectional() {
        const wallpaper = { wallpaperManager: true, launcher: false, session: false, dashboard: false, utilities: false, sidebar: false, overview: false, clipboard: false, hardware: false, displayManager: false };
        const competing = { wallpaperManager: true, launcher: true, session: true, dashboard: true, utilities: true, sidebar: true, overview: true, clipboard: true, hardware: true, displayManager: true };
        OverlayPolicy.closeForWallpaper(competing);
        verify(competing.wallpaperManager);
        verify(!OverlayPolicy.hasCompetingPanel(competing));
        OverlayPolicy.closeOtherPanels(wallpaper);
        verify(!wallpaper.wallpaperManager);
    }
    function test_pixel_wheel_threshold() {
        let intent = Orbit.wheelIntent(0, 0, 39);
        compare(intent.direction, 0);
        intent = Orbit.wheelIntent(intent.accumulator, 0, 1);
        compare(intent.direction, -1);
        compare(intent.accumulator, 0);
    }
    function test_only_final_stable_candidate_previews() {
        verify(!Orbit.previewEligible("B", "D", true, false, 0));
        verify(!Orbit.previewEligible("D", "D", false, false, 0));
        verify(!Orbit.previewEligible("D", "D", true, true, 0));
        verify(!Orbit.previewEligible("D", "D", true, false, -1));
        verify(Orbit.previewEligible("D", "D", true, false, 0));
    }
}
