import QtQuick
import QtTest
import "../../../modules/hardware/summary"

TestCase {
    id: testCase
    name: "HardwareNavBlock"
    when: windowShown
    visible: true
    width: 400
    height: 200

    Component {
        id: pair

        Column {
            property int activations: 0
            property alias first: first
            property alias second: second

            NavBlock {
                id: first
                width: 300; height: 60
                destination: "Rendimiento"
                accessibleName: "CPU"
                onActivated: parent.activations += 1
            }
            NavBlock {
                id: second
                width: 300; height: 60
                destination: "Procesos"
            }
        }
    }

    function test_enter_return_and_space_activate() {
        const item = createTemporaryObject(pair, testCase);
        item.first.forceActiveFocus();
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Enter);
        keyClick(Qt.Key_Space);
        compare(item.activations, 3);
    }

    function test_click_activates_and_takes_focus() {
        const item = createTemporaryObject(pair, testCase);
        mouseClick(item.first);
        compare(item.activations, 1);
        verify(item.first.activeFocus);
    }

    function test_tab_walks_blocks_in_order() {
        const item = createTemporaryObject(pair, testCase);
        item.first.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        verify(item.second.activeFocus);
        keyClick(Qt.Key_Backtab);
        verify(item.first.activeFocus);
    }

    function test_hover_and_focus_name_the_destination() {
        const item = createTemporaryObject(pair, testCase);
        verify(!item.first.engaged);
        item.first.forceActiveFocus();
        verify(item.first.engaged);
        verify(!item.second.engaged);
        mouseMove(item.second, 10, 10);
        tryVerify(() => item.second.engaged);
    }

    function test_exposes_itself_as_a_named_button() {
        const item = createTemporaryObject(pair, testCase);
        compare(item.first.Accessible.role, Accessible.Button);
        compare(item.first.Accessible.name, "CPU");
        compare(item.first.Accessible.description, "Rendimiento");
    }
}
