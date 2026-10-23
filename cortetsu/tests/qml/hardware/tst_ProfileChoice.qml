import QtQuick
import QtTest
import "../../../modules/hardware"

TestCase {
    id: testCase
    name: "ProfileChoiceGuard"
    when: windowShown
    visible: true
    width: 400
    height: 220

    Component {
        id: choice
        ProfileChoice {
            width: 320
            profile: "balanced"
            property int requests: 0
            onChosen: requests++
        }
    }

    function test_accessible_activation_obeys_busy_and_disabled_states() {
        const item = createTemporaryObject(choice, testCase);
        compare(item.Accessible.role, Accessible.RadioButton);
        item.Accessible.pressAction();
        compare(item.requests, 1);
        item.busy = true;
        item.Accessible.pressAction();
        compare(item.requests, 1);
        item.busy = false;
        item.disabled = true;
        item.Accessible.pressAction();
        compare(item.requests, 1);
        item.disabled = false;
        item.Accessible.pressAction();
        compare(item.requests, 2);
    }

    function test_keyboard_and_pointer_use_the_same_request_guard() {
        const item = createTemporaryObject(choice, testCase);
        item.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(item.requests, 1);
        item.busy = true;
        keyClick(Qt.Key_Space);
        mouseClick(item, item.width / 2, item.height / 2);
        compare(item.requests, 1);
        item.busy = false;
        keyClick(Qt.Key_Space);
        compare(item.requests, 2);
    }
}
