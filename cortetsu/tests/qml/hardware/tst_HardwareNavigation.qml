import QtQuick
import QtTest
import "../../../modules/hardware/Navigation.js" as HardwareNavigation

TestCase {
    name: "HardwareNavigation"

    function test_zero_selects_last_tab() {
        verify(HardwareNavigation.handlesPageKey(Qt.Key_0, Qt.Key_1, Qt.Key_9, Qt.Key_0));
        compare(HardwareNavigation.pageForKey(Qt.Key_0, 2, Qt.Key_1, Qt.Key_9, Qt.Key_0), HardwareNavigation.lastPage);
        compare(HardwareNavigation.lastPage, 9, "Sistema is the tenth tab");
        compare(HardwareNavigation.pages.system, HardwareNavigation.lastPage);
    }

    function test_seven_selects_seventh_tab() {
        verify(HardwareNavigation.handlesPageKey(Qt.Key_7, Qt.Key_1, Qt.Key_9, Qt.Key_0));
        compare(HardwareNavigation.pageForKey(Qt.Key_7, 2, Qt.Key_1, Qt.Key_9, Qt.Key_0), 6);
    }

    function test_escape_is_recognized() {
        verify(HardwareNavigation.isEscape(Qt.Key_Escape, Qt.Key_Escape));
        verify(!HardwareNavigation.isEscape(Qt.Key_7, Qt.Key_Escape));
    }

    // Fn+Esc: open on Sistema, close when Sistema shows, switch otherwise.
    function test_page_action() {
        const system = HardwareNavigation.pages.system;
        compare(HardwareNavigation.pageAction(false, 0, system), "open");
        compare(HardwareNavigation.pageAction(false, system, system), "open");
        compare(HardwareNavigation.pageAction(true, system, system), "close");
        compare(HardwareNavigation.pageAction(true, 2, system), "switch");
    }

    function test_duplicate_press_is_dropped() {
        verify(HardwareNavigation.acceptPress(0, 1000, 400), "first press");
        verify(!HardwareNavigation.acceptPress(1000, 1001, 400), "duplicate report");
        verify(!HardwareNavigation.acceptPress(1000, 1399, 400));
        verify(HardwareNavigation.acceptPress(1000, 1400, 400), "a second deliberate press");
        verify(HardwareNavigation.acceptPress(5000, 1000, 400), "clock went back");
    }
}
