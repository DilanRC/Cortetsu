import QtQuick
import QtTest
import "../../../modules/drawers/HoverEdges.js" as HoverEdges

TestCase {
    name: "HoverEdges"

    function test_closed_top_and_bottom_edges_are_reachable() {
        compare(HoverEdges.dragRegionInset(1, 0), 2);
        compare(HoverEdges.dragRegionHeight(1080, 1, 0), 1075);
        verify(HoverEdges.containsTop(1, 1, 1, 0));
        verify(!HoverEdges.containsTop(2, 1, 1, 0));
        verify(HoverEdges.containsBottom(1078, 1080, 1, 1, 0));
        verify(!HoverEdges.containsBottom(1077, 1080, 1, 1, 0));
    }

    function test_drag_padding_preserves_the_reachable_screen_edges() {
        compare(HoverEdges.dragRegionInset(1, 40), 42);
        compare(HoverEdges.dragRegionHeight(1080, 1, 40), 995);
        verify(HoverEdges.containsTop(101, 1, 1, 100));
        verify(!HoverEdges.containsTop(102, 1, 1, 100));
        verify(HoverEdges.containsBottom(978, 1080, 1, 1, 100));
        verify(!HoverEdges.containsBottom(977, 1080, 1, 1, 100));
    }
}
