import QtQuick
import QtTest
import "../../../modules/polkit"

// The dialog drives a Quickshell AuthFlow. The stand-in below has the same
// properties and methods and records what the dialog sends back.
TestCase {
    id: testCase
    name: "PolkitDialog"
    when: windowShown
    visible: true
    width: 600
    height: 500

    Component {
        id: flowComponent
        QtObject {
            property string message: "Authentication is required to run a program as root"
            property string actionId: "org.freedesktop.policykit.exec"
            property var identities: []
            property var selectedIdentity: null
            property bool isResponseRequired: true
            property string inputPrompt: "Password: "
            property bool responseVisible: false
            property string supplementaryMessage: ""
            property bool supplementaryIsError: false
            property bool isCompleted: false
            property bool failed: false
            property var submitted: []
            property int cancels: 0
            function submit(value) { submitted = submitted.concat([value]); isResponseRequired = false; }
            function cancelAuthenticationRequest() { cancels += 1; }
        }
    }

    Component {
        id: identityComponent
        QtObject { property string displayName }
    }

    Component {
        id: dialogComponent
        PolkitDialog {}
    }

    function make(overrides) {
        const flow = createTemporaryObject(flowComponent, testCase, overrides || {});
        const dialog = createTemporaryObject(dialogComponent, testCase, { flow: flow });
        verify(dialog);
        return { flow: flow, dialog: dialog, field: findChild(dialog, "password") };
    }

    function test_enter_submits_and_clears_the_password() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        compare(t.field.echoMode, TextInput.Password);
        keyClick("s"); keyClick("3"); keyClick("c");
        keyClick(Qt.Key_Return);
        compare(t.flow.submitted, ["s3c"]);
        compare(t.field.text, "");
        verify(!t.field.enabled, "no second answer until polkit asks again");
    }

    function test_empty_password_is_not_sent() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick(Qt.Key_Return);
        compare(t.flow.submitted.length, 0);
        verify(findChild(t.dialog, "authenticate").disabled);
    }

    function test_escape_cancels_the_request() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick("x");
        keyClick(Qt.Key_Escape);
        compare(t.flow.cancels, 1);
        compare(t.field.text, "");
    }

    function test_escape_cancels_while_polkit_has_not_asked_yet() {
        const t = make({ isResponseRequired: false });
        verify(!t.field.enabled);
        keyClick(Qt.Key_Escape);
        compare(t.flow.cancels, 1);
    }

    // A cancel must only cancel: an empty or partial answer sent to PAM would
    // be a real failed attempt for pam_faillock.
    function test_cancel_never_sends_an_answer() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick("x");
        mouseClick(findChild(t.dialog, "cancel"));
        compare(t.flow.cancels, 1);
        compare(t.flow.submitted.length, 0);
    }

    function test_escape_cancels_while_pam_checks_the_answer() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick("x");
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Escape);
        compare(t.flow.submitted, ["x"]);
        compare(t.flow.cancels, 1);
    }

    function test_retry_after_a_wrong_password_sends_the_new_one() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick("a");
        keyClick(Qt.Key_Return);
        t.flow.failed = true;
        t.flow.isResponseRequired = true;
        tryVerify(() => t.field.enabled && t.field.activeFocus);
        compare(t.field.text, "");
        keyClick("b");
        keyClick(Qt.Key_Return);
        compare(t.flow.submitted, ["a", "b"]);
        compare(t.flow.cancels, 0);
    }

    function test_finished_request_ignores_escape() {
        const t = make({ isResponseRequired: false, isCompleted: true });
        keyClick(Qt.Key_Escape);
        compare(t.flow.cancels, 0);
    }

    function test_wrong_password_shows_an_error_and_refocuses() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick("x");
        keyClick(Qt.Key_Return);
        const feedback = findChild(t.dialog, "feedback");
        verify(!feedback.visible);
        t.flow.failed = true;
        t.flow.isResponseRequired = true;
        verify(feedback.visible);
        verify(feedback.isError);
        tryVerify(() => t.field.enabled && t.field.activeFocus);
    }

    function test_visible_response_and_prompt_come_from_polkit() {
        const t = make({ responseVisible: true, inputPrompt: "PIN: " });
        compare(t.field.echoMode, TextInput.Normal);
        compare(t.field.placeholderText, "PIN");
    }

    function test_supplementary_message_is_shown() {
        const t = make({ supplementaryMessage: "Swipe your finger", supplementaryIsError: false });
        const feedback = findChild(t.dialog, "feedback");
        verify(feedback.visible);
        compare(feedback.text, "Swipe your finger");
        verify(!feedback.isError);
    }

    function test_identity_switch_cycles_through_identities() {
        const a = createTemporaryObject(identityComponent, testCase, { displayName: "dilan" });
        const b = createTemporaryObject(identityComponent, testCase, { displayName: "root" });
        const t = make({ identities: [a, b], selectedIdentity: a });
        const button = findChild(t.dialog, "switchIdentity");
        verify(button.visible);
        compare(findChild(t.dialog, "identity").text, "Como dilan");
        t.dialog.nextIdentity();
        compare(t.flow.selectedIdentity, b);
        compare(findChild(t.dialog, "identity").text, "Como root");
        t.dialog.nextIdentity();
        compare(t.flow.selectedIdentity, a);
    }

    function test_single_identity_hides_the_switch() {
        const a = createTemporaryObject(identityComponent, testCase, { displayName: "dilan" });
        const t = make({ identities: [a], selectedIdentity: a });
        verify(!findChild(t.dialog, "switchIdentity").visible);
    }
}
