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

    function test_popout_opens_out_of_its_control() {
        // A 400 x 300 popout at (760, 712) over a bottom Hub, opened by a
        // control at 1000: it grows from the bottom edge, 240 px in.
        compare(HubAnchor.popoutOrigin("bottom-center", 1000, 760, 712, 400, 300), { x: 240, y: 300 });
        compare(HubAnchor.popoutOrigin("top-right", 1000, 760, 68, 400, 300), { x: 240, y: 0 });
        compare(HubAnchor.popoutOrigin("middle-left", 500, 68, 400, 400, 300), { x: 0, y: 100 });
        compare(HubAnchor.popoutOrigin("middle-right", 500, 1452, 400, 400, 300), { x: 400, y: 100 });
        // A control past the popout's end (it was clamped into the screen)
        // keeps the origin on the popout; no control: the middle.
        compare(HubAnchor.popoutOrigin("bottom-left", 5, 8, 712, 400, 300), { x: 0, y: 300 });
        compare(HubAnchor.popoutOrigin("bottom-right", 1915, 1512, 712, 400, 300), { x: 400, y: 300 });
        compare(HubAnchor.popoutOrigin("bottom-center", -1, 760, 712, 400, 300), { x: 200, y: 300 });
    }

    function test_grid_holds_each_anchor_once() {
        const flat = [].concat(...HubAnchor.grid).filter(id => id !== "");
        compare(flat.slice().sort(), HubAnchor.ids.slice().sort());
        compare(HubAnchor.grid[1][1], "");
    }

    function test_move_walks_the_screen() {
        compare(HubAnchor.move("bottom-center", -1, 0), "bottom-left");
        compare(HubAnchor.move("bottom-left", -1, 0), "bottom-left");
        compare(HubAnchor.move("bottom-center", 0, -1), "top-center");  // over the centre
        compare(HubAnchor.move("middle-left", 1, 0), "middle-right");   // over the centre
        compare(HubAnchor.move("middle-left", 0, -1), "top-left");
        compare(HubAnchor.move("top-right", 1, 1), "middle-right");
        compare(HubAnchor.move("junk", 1, 0), "bottom-right");
        compare(Object.keys(HubAnchor.labels).sort(), HubAnchor.ids.slice().sort());
    }

    function test_footprint_matches_the_edge() {
        const f = id => HubAnchor.footprint(id, 1920, 1080, 56, 600, 8, 8);
        compare(f("bottom-center"), { x: 8, y: 1080 - 8 - 56, width: 1904, height: 56 });
        compare(f("top-left"), { x: 16, y: 8, width: 600, height: 56 });
        compare(f("bottom-right"), { x: 1920 - 16 - 600, y: 1016, width: 600, height: 56 });
        compare(f("middle-left"), { x: 8, y: 8, width: 56, height: 1064 });
        compare(f("middle-right"), { x: 1920 - 8 - 56, y: 8, width: 56, height: 1064 });
        // The real Hub keeps 2 px from its edge and 8 px at the ends.
        compare(HubAnchor.footprint("bottom-center", 1920, 1080, 56, 600, 8, 8, 2), { x: 8, y: 1022, width: 1904, height: 56 });
        compare(HubAnchor.footprint("middle-left", 1920, 1080, 56, 600, 8, 8, 2), { x: 2, y: 8, width: 56, height: 1064 });
    }

    function test_footprint_stays_on_screen_data() {
        const rows = [];
        for (const id of HubAnchor.ids)
            for (const length of [0, 300, 1800, 9000])
                for (const area of [[1920, 1080], [1536, 864], [800, 600]])
                    rows.push({ tag: `${id} ${length} ${area}`, id: id, length: length, area: area });
        return rows;
    }

    function test_footprint_stays_on_screen(data) {
        const r = HubAnchor.footprint(data.id, data.area[0], data.area[1], 56, data.length, 8, 8);
        verify(r.x >= 8 && r.y >= 8, `starts inside (${r.x}, ${r.y})`);
        verify(r.x + r.width <= data.area[0] - 8, `right edge inside (${r.x + r.width})`);
        verify(r.y + r.height <= data.area[1] - 8, `bottom edge inside (${r.y + r.height})`);
        verify(r.width >= 56 && r.height >= 56, `never thinner than the Hub (${r.width} x ${r.height})`);
    }

    function test_nearest_anchor_data() {
        return [
            { tag: "bottom middle", x: 960, y: 1070, want: "bottom-center" },
            { tag: "bottom left", x: 100, y: 1000, want: "bottom-left" },
            { tag: "bottom right", x: 1900, y: 1000, want: "bottom-right" },
            { tag: "top left", x: 10, y: 10, want: "top-left" },
            { tag: "top middle", x: 960, y: 0, want: "top-center" },
            { tag: "top right", x: 1919, y: 200, want: "top-right" },
            { tag: "left", x: 50, y: 540, want: "middle-left" },
            { tag: "right", x: 1870, y: 540, want: "middle-right" },
            { tag: "centre, nearer the bottom", x: 960, y: 700, want: "bottom-center" },
            { tag: "centre, nearer the top", x: 960, y: 380, want: "top-center" },
            { tag: "centre, nearer the left", x: 650, y: 540, want: "middle-left" },
            { tag: "centre, nearer the right", x: 1270, y: 540, want: "middle-right" },
            { tag: "off screen", x: -400, y: 5000, want: "bottom-left" },
            { tag: "no screen", x: 10, y: 10, w: 0, want: "bottom-center" },
            { tag: "not a number", x: NaN, y: 10, want: "bottom-center" }
        ];
    }

    function test_nearest_anchor(data) {
        compare(HubAnchor.nearest(data.x, data.y, data.w ?? 1920, 1080), data.want);
    }

    function test_reserved_edge() {
        compare(HubAnchor.reserved("top-left", 60), { top: 60, bottom: 0, left: 0, right: 0 });
        compare(HubAnchor.reserved("middle-right", 60), { top: 0, bottom: 0, left: 0, right: 60 });
        compare(HubAnchor.reserved("junk", 60), { top: 0, bottom: 60, left: 0, right: 0 });
    }
}
