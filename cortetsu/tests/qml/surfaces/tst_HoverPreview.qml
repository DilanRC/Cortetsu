import QtQuick
import QtTest
import "../../../modules/drawers/HoverPreview.js" as HoverPreview

TestCase {
    name: "HoverPreview"

    readonly property var panel: ({ x: 100, y: 100, width: 400, height: 400 })
    readonly property var trigger: ({ x: 0, y: 980, width: 1920, height: 100 })
    readonly property var launcherButton: ({ x: 934, y: 1000, width: 44, height: 44 })

    function test_panel_and_trigger_keep_preview_open(): void {
        verify(HoverPreview.shouldKeepOpen(
            HoverPreview.contains(panel, 120, 130),
            HoverPreview.contains(trigger, 120, 130)
        ));
        verify(HoverPreview.shouldKeepOpen(
            HoverPreview.contains(panel, 960, 1070),
            HoverPreview.contains(trigger, 960, 1070)
        ));
        verify(!HoverPreview.shouldKeepOpen(
            HoverPreview.contains(panel, 960, 600),
            HoverPreview.contains(trigger, 960, 600)
        ));
    }

    function test_bottom_hub_launcher_button_is_an_explicit_promotion_target(): void {
        verify(HoverPreview.shouldKeepOpen(false, false, true));
        verify(!HoverPreview.shouldKeepOpen(false, false, false));
    }

    function test_rect_edges_match_half_open_pointer_bounds(): void {
        verify(HoverPreview.contains(panel, 100, 100));
        verify(!HoverPreview.contains(panel, 500, 500));
        verify(!HoverPreview.contains(panel, 99, 100));
        verify(HoverPreview.contains(trigger, 950, 1020));
        verify(HoverPreview.contains(launcherButton, 950, 1020));
        verify(!HoverPreview.contains(launcherButton, 1000, 1020));
    }
}
