import QtQuick
import QtTest
import "../../../modules/hardware/Navigation.js" as HardwareNavigation

TestCase {
    name: "HardwareNavigation"

    function test_zero_selects_last_tab() {
        verify(HardwareNavigation.handlesPageKey(Qt.Key_0, Qt.Key_1, Qt.Key_9, Qt.Key_0));
        compare(HardwareNavigation.pageForKey(Qt.Key_0, 2, Qt.Key_1, Qt.Key_9, Qt.Key_0), 9);
    }

    function test_seven_selects_seventh_tab() {
        verify(HardwareNavigation.handlesPageKey(Qt.Key_7, Qt.Key_1, Qt.Key_9, Qt.Key_0));
        compare(HardwareNavigation.pageForKey(Qt.Key_7, 2, Qt.Key_1, Qt.Key_9, Qt.Key_0), 6);
    }

    function test_escape_is_recognized() {
        verify(HardwareNavigation.isEscape(Qt.Key_Escape, Qt.Key_Escape));
        verify(!HardwareNavigation.isEscape(Qt.Key_7, Qt.Key_Escape));
    }
}
