import QtQuick
import QtTest

TestCase {
    name: "OsdEscape"
    when: windowShown

    Item {
        id: host
        width: 200
        height: 100
        focus: true
        property bool osdOpen: false

        Shortcut {
            sequence: "Escape"
            enabled: host.osdOpen
            onActivated: host.osdOpen = false
        }
    }

    function test_escape_closes_an_open_osd() {
        host.osdOpen = true;
        host.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        tryCompare(host, "osdOpen", false);
    }

    function test_escape_does_not_change_a_closed_osd() {
        host.osdOpen = false;
        host.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(host.osdOpen, false);
    }
}
