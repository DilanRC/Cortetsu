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
    function test_bounded_windows_data() {
        return [
            {tag: "empty", count: 0, expected: 0}, {tag: "one", count: 1, expected: 1},
            {tag: "two", count: 2, expected: 2}, {tag: "twelve", count: 12, expected: 12},
            {tag: "thirteen", count: 13, expected: 12}, {tag: "hundreds", count: 300, expected: 12}
        ];
    }
    function test_bounded_windows(data) { compare(Orbit.visible(paths(data.count), 0, 12).length, data.expected); }
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
    function test_satellites_exclude_selected_data() {
        return [
            {tag: "one", count: 1, expected: 0}, {tag: "two", count: 2, expected: 1},
            {tag: "hundreds", count: 300, expected: 11}
        ];
    }
    function test_satellites_exclude_selected(data) {
        const entries = paths(data.count);
        const selected = data.count ? data.count - 1 : -1;
        const satellites = Orbit.satellites(entries, selected, selected, 12);
        compare(satellites.length, data.expected);
        for (let i = 0; i < satellites.length; ++i) {
            verify(satellites[i].index !== selected);
            compare(satellites[i].entry.path, entries[satellites[i].index].path);
        }
    }
    function test_satellite_wrap_and_target_index() {
        const entries = paths(20);
        const satellites = Orbit.satellites(entries, 0, 0, 12);
        compare(satellites.length, 11);
        verify(satellites.some(item => item.index === 19));
        verify(satellites.some(item => item.index === 1));
        const target = satellites.find(item => item.index === 19);
        compare(target.index, 19);
        compare(target.entry.path, entries[19].path);
    }
    function test_wrap_and_unicode() {
        compare(Orbit.move(0, -1, 13), 12);
        compare(Orbit.move(12, 1, 13), 0);
        const entries = [{path: "/walls/日本/星 空.webp"}, {path: "/walls/night/luna.png"}];
        compare(Orbit.filtered(entries, "日本", entry => entry.path.split("/")[2])[0].path, "/walls/日本/星 空.webp");
    }
    function test_rotation_contract() {
        compare(Orbit.angularStep(12), Math.PI / 6);
        compare(Orbit.shortestSteps(0, 12, 13), -1);
        compare(Orbit.shortestSteps(0, 7, 12), -5);
        compare(Orbit.satelliteTarget(6, 0, 12, 20), 0);
        verify(Orbit.satelliteAngle(0, 12, 0) !== Orbit.satelliteAngle(0, 12, -Orbit.angularStep(12)));
    }
    function test_categories() {
        const entries = [{kind: "fog"}, {kind: "night"}, {kind: "fog"}];
        compare(Orbit.categories(entries, entry => entry.kind).join(","), "ALL,fog,night");
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
