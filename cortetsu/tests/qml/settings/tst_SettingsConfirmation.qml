import QtQuick
import QtTest
import "../../../modules/settings/controls"

TestCase {
    id: testCase
    name: "SettingsConfirmation"
    when: windowShown
    visible: true
    width: 520
    height: 240

    Component {
        id: confirmationFixture
        SettingActionRow {
            width: 440
            title: "Vaciar historial"
            actionLabel: "Vaciar"
            danger: true
            confirm: true
            property int activations: 0
            onActivated: activations++
        }
    }

    function test_confirmation_needs_two_requests() {
        const item = createTemporaryObject(confirmationFixture, testCase);
        item.request();
        verify(item.armed);
        compare(item.activations, 0);
        item.request();
        compare(item.activations, 1);
        verify(!item.armed);
    }

    function test_busy_or_disabled_cancels_the_pending_confirmation() {
        const item = createTemporaryObject(confirmationFixture, testCase);
        item.request();
        item.status = "busy";
        verify(!item.armed);
        item.request();
        compare(item.activations, 0);
        item.status = "";
        item.request();
        verify(item.armed);
        item.disabled = true;
        verify(!item.armed);
        item.disabled = false;
        item.request();
        compare(item.activations, 0);
        verify(item.armed);
    }

    function test_changed_action_and_hidden_row_cannot_reuse_confirmation() {
        const item = createTemporaryObject(confirmationFixture, testCase);
        item.request();
        item.title = "Otra operación";
        verify(!item.armed);
        item.request();
        verify(item.armed);
        item.visible = false;
        verify(!item.armed);
        item.request();
        compare(item.activations, 0);
    }
}
