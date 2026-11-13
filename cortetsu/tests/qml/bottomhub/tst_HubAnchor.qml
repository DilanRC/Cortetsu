import QtQuick
import QtTest
import "../../../modules/HubAnchor.js" as HubAnchor

// The Hub's eight anchors as pure geometry: a damaged preference falls back
// to the bottom, and an attached popout always opens inside the screen.
TestCase {
    name: "HubAnchor"

    function test_eight_anchors() {
        compare(HubAnchor.ids.length, 8);
        for (const id of HubAnchor.ids)
            compare(HubAnchor.describe(id).id, id);
        verify(HubAnchor.describe("middle-left").vertical);
        verify(HubAnchor.describe("middle-right").vertical);
        verify(!HubAnchor.describe("top-right").vertical);
        compare(HubAnchor.describe("top-right").pack, "end");
        compare(HubAnchor.describe("bottom-center").pack, "spread");
    }

    function test_unknown_values_fall_back_to_the_bottom_data() {
        return [{ value: undefined }, { value: "" }, { value: "centre" }, { value: 4 }, { value: "__proto__" }, { value: "toString" }];
    }

    function test_unknown_values_fall_back_to_the_bottom(data) {
        compare(HubAnchor.normalize(data.value), "bottom-center");
        compare(HubAnchor.describe(data.value).edge, "bottom");
    }

    function test_monitor_entry_wins_over_the_default() {
        const map = { "HDMI-A-1": "top-right", "DP-9": "nowhere" };
        compare(HubAnchor.forMonitor("middle-left", map, "HDMI-A-1"), "top-right");
        compare(HubAnchor.forMonitor("middle-left", map, "eDP-1"), "middle-left");
        compare(HubAnchor.forMonitor("middle-left", map, "DP-9"), "middle-left");
        compare(HubAnchor.forMonitor("bogus", null, "eDP-1"), "bottom-center");
    }

    function test_map_drops_what_it_does_not_know() {
        const clean = HubAnchor.sanitizeMap({ "eDP-1": "top-left", "": "top-left", "DP-1": "side", "DP-2": 3 });
        compare(Object.keys(clean), ["eDP-1"]);
        compare(Object.keys(HubAnchor.sanitizeMap([1, 2])).length, 0);
        compare(Object.keys(HubAnchor.sanitizeMap("x")).length, 0);
    }

    function test_popout_opens_inwards_from_each_edge() {
        const at = id => HubAnchor.popoutPosition(id, 960, 400, 300, 1920, 1080, 60, 8, 8);
        compare(at("bottom-center"), { x: 760, y: 1080 - 300 - 68 });
        compare(at("top-center"), { x: 760, y: 68 });
        compare(at("middle-left"), { x: 68, y: 772 });
        compare(at("middle-right"), { x: 1920 - 400 - 68, y: 772 });
    }

    function test_popout_never_leaves_the_screen_data() {
        const rows = [];
        for (const id of HubAnchor.ids)
            for (const along of [-1, 0, 5, 700, 1915, 5000])
                for (const size of [[400, 300], [1900, 1060], [2400, 1400]])
                    for (const area of [[1920, 1080], [1536, 864], [880, 620]])
                        rows.push({ tag: `${id} ${along} ${size} ${area}`, id: id, along: along, size: size, area: area });
        return rows;
    }

    function test_popout_never_leaves_the_screen(data) {
        const p = HubAnchor.popoutPosition(data.id, data.along, data.size[0], data.size[1], data.area[0], data.area[1], 60, 8, 8);
        verify(p.x >= 8 && p.y >= 8, `starts inside (${p.x}, ${p.y})`);
        // A popout larger than the screen keeps its origin inside; one that
        // fits is wholly inside.
        if (data.size[0] + 16 <= data.area[0])
            verify(p.x + data.size[0] <= data.area[0] - 8, `right edge inside (${p.x})`);
        if (data.size[1] + 16 <= data.area[1])
            verify(p.y + data.size[1] <= data.area[1] - 8, `bottom edge inside (${p.y})`);
    }

    function test_reserved_edge() {
        compare(HubAnchor.reserved("top-left", 60), { top: 60, bottom: 0, left: 0, right: 0 });
        compare(HubAnchor.reserved("middle-right", 60), { top: 0, bottom: 0, left: 0, right: 60 });
        compare(HubAnchor.reserved("junk", 60), { top: 0, bottom: 60, left: 0, right: 0 });
    }

    function test_nearest_anchor_covers_the_whole_screen() {
        compare(HubAnchor.nearest(10, 10, 1920, 1080), "top-left");
        compare(HubAnchor.nearest(960, 10, 1920, 1080), "top-center");
        compare(HubAnchor.nearest(1900, 1070, 1920, 1080), "bottom-right");
        compare(HubAnchor.nearest(10, 540, 1920, 1080), "middle-left");
        compare(HubAnchor.nearest(960, 700, 1920, 1080), "bottom-center");
        compare(HubAnchor.nearest(700, 540, 1920, 1080), "middle-left");
        for (let x = 0; x <= 1920; x += 96)
            for (let y = 0; y <= 1080; y += 54)
                verify(HubAnchor.valid(HubAnchor.nearest(x, y, 1920, 1080)), `(${x}, ${y})`);
    }
}
