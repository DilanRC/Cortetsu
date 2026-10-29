import QtQuick
import QtTest
import "../../../modules/prompt"

// SecretPrompt shows one request line and reports the answer through
// `answered`. Each case uses the shape gnome-keyring or pinentry-gnome3 sends
// through cortetsu-prompter, or NetworkManager and BlueZ through
// cortetsu-agents (desktop-runtime-rs/src/agents.rs).
TestCase {
    id: testCase
    name: "SecretPrompt"
    when: windowShown
    visible: true
    width: 600
    height: 600

    Component {
        id: dialogComponent
        SecretPrompt {
            property var answers: []
            property var identities: []
            onAnswered: (accepted, password, choice, identity) => {
                answers = answers.concat([[accepted, password, choice]]);
                identities = identities.concat([identity]);
            }
        }
    }

    function line(overrides) {
        return Object.assign({ token: "t", kind: "password", title: "", message: "Desbloquear el llavero de inicio de sesión",
            description: "Una aplicación quiere acceder al llavero «login».", warning: "", choiceLabel: "",
            choiceChosen: false, passwordNew: false, continueLabel: "", cancelLabel: "" }, overrides || {});
    }

    function make(overrides) {
        const dialog = createTemporaryObject(dialogComponent, testCase, { prompt: line(overrides) });
        verify(dialog);
        return { dialog: dialog, field: findChild(dialog, "password"), confirm: findChild(dialog, "confirm") };
    }

    function type(text) {
        for (const c of text)
            keyClick(c);
    }

    function test_enter_answers_with_the_password_and_clears_it() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        compare(findChild(t.dialog, "heading").text, "Desbloquear el llavero de inicio de sesión");
        verify(findChild(t.dialog, "description").visible);
        type("s3c");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "s3c", false]]);
        compare(t.field.text, "");
    }

    function test_unlock_needs_a_password() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers.length, 0);
        verify(findChild(t.dialog, "continue").disabled);
    }

    function test_escape_cancels_also_while_waiting() {
        const t = make();
        t.dialog.waiting = true;
        verify(!t.field.enabled);
        keyClick(Qt.Key_Escape);
        compare(t.dialog.answers, [[false, "", false]]);
    }

    function test_waiting_blocks_a_second_answer_and_says_so() {
        const t = make();
        t.dialog.waiting = true;
        const feedback = findChild(t.dialog, "feedback");
        compare(feedback.text, "Comprobando…");
        verify(!feedback.isError);
        t.dialog.accept();
        compare(t.dialog.answers.length, 0);
    }

    function test_retry_shows_the_warning_and_refocuses() {
        const t = make();
        tryVerify(() => t.field.activeFocus);
        type("mal");
        keyClick(Qt.Key_Return);
        t.dialog.waiting = true;
        t.dialog.prompt = line({ warning: "La contraseña no es correcta" });
        t.dialog.waiting = false;
        const feedback = findChild(t.dialog, "feedback");
        compare(feedback.text, "La contraseña no es correcta");
        verify(feedback.isError);
        tryVerify(() => t.field.enabled && t.field.activeFocus);
    }

    function test_new_keyring_needs_the_same_password_twice() {
        const t = make({ passwordNew: true, message: "Elige una contraseña para el llavero nuevo" });
        verify(t.confirm.visible);
        tryVerify(() => t.field.activeFocus);
        type("uno");
        keyClick(Qt.Key_Return);
        verify(t.confirm.activeFocus, "Enter moves to the second field");
        type("dos");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers.length, 0);
        compare(findChild(t.dialog, "feedback").text, "Las contraseñas no coinciden.");
        t.confirm.clear();
        t.confirm.forceActiveFocus();
        type("uno");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "uno", false]]);
    }

    function test_new_keyring_may_be_blank() {
        // gnome-keyring asks itself whether to store unencrypted.
        const t = make({ passwordNew: true });
        verify(!findChild(t.dialog, "continue").disabled);
        t.dialog.accept();
        compare(t.dialog.answers, [[true, "", false]]);
    }

    function test_confirm_prompt_has_no_field_and_enter_continues() {
        const t = make({ kind: "confirm", message: "¿Guardar las contraseñas sin cifrar?",
            continueLabel: "_Continue", cancelLabel: "_Cancel" });
        verify(!t.field.visible && !t.confirm.visible);
        const button = findChild(t.dialog, "continue");
        compare(button.label, "Continue");
        compare(findChild(t.dialog, "cancel").label, "Cancel");
        tryVerify(() => button.activeFocus);
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "", false]]);
    }

    function test_choice_is_sent_back() {
        const t = make({ choiceLabel: "Desbloquear automáticamente al iniciar sesión", choiceChosen: true });
        const row = findChild(t.dialog, "choiceRow");
        verify(row.visible);
        const toggle = findChild(t.dialog, "choice");
        verify(toggle.checked);
        toggle.toggled(false);
        tryVerify(() => t.field.activeFocus);
        type("pw");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "pw", false]]);
    }

    function test_no_choice_hides_the_row() {
        const t = make();
        verify(!findChild(t.dialog, "choiceRow").visible);
    }

    function test_mnemonics_are_dropped_from_labels() {
        const t = make();
        compare(t.dialog.label("_OK", "x"), "OK");
        compare(t.dialog.label("Save__as", "x"), "Save_as");
        compare(t.dialog.label("", "Cancelar"), "Cancelar");
    }

    function test_pinentry_shape_names_the_caller() {
        // As pinentry-gnome3 1.3.3 sends it for `gpg --clearsign`.
        const t = make({ title: "[182068]@stelar (gpg --clearsign)", message: "Frase contraseña:",
            description: "Introduce la frase de contraseña:\n\"prueba\"\n", continueLabel: "_OK", cancelLabel: "_Cancelar" });
        compare(findChild(t.dialog, "heading").text, "Frase contraseña");
        const caller = findChild(t.dialog, "caller");
        verify(caller.visible);
        compare(caller.text, "[182068]@stelar (gpg --clearsign)");
        compare(findChild(t.dialog, "description").text, "Introduce la frase de contraseña:\n\"prueba\"");
        compare(findChild(t.dialog, "continue").label, "OK");
    }

    function test_empty_message_has_a_heading() {
        const t = make({ message: "" });
        compare(findChild(t.dialog, "heading").text, "Contraseña requerida");
        verify(!findChild(t.dialog, "caller").visible);
    }

    function test_wifi_password_needs_eight_characters() {
        const t = make({ icon: "wifi_password", message: "Contraseña de «Casa 5G»", minLength: 8, maxLength: 64,
            passwordLabel: "Contraseña", continueLabel: "Conectar" });
        tryVerify(() => t.field.activeFocus);
        compare(t.field.echoMode, TextInput.Password);
        type("corta");
        const feedback = findChild(t.dialog, "feedback");
        compare(feedback.text, "Al menos 8 caracteres.");
        verify(!feedback.isError, "a hint while typing, not an error");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers.length, 0);
        type("larga");
        verify(!feedback.visible);
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "cortalarga", false]]);
    }

    function test_enterprise_sends_user_and_password() {
        const t = make({ message: "Inicio de sesión en «Campus»", identityLabel: "Usuario", identity: "",
            passwordLabel: "Contraseña" });
        const identity = findChild(t.dialog, "identity");
        verify(identity.visible);
        tryVerify(() => identity.activeFocus, 1000, "an empty user field takes the focus first");
        type("ana");
        keyClick(Qt.Key_Return);
        verify(t.field.activeFocus, "Enter moves to the password");
        type("pw");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "pw", false]]);
        compare(t.dialog.identities, ["ana"]);
    }

    function test_enterprise_prefills_the_saved_user() {
        const t = make({ identityLabel: "Usuario", identity: "ana@una.ac.cr" });
        compare(findChild(t.dialog, "identity").text, "ana@una.ac.cr");
        tryVerify(() => t.field.activeFocus);
        findChild(t.dialog, "identity").clear();
        type("x");
        verify(findChild(t.dialog, "continue").disabled, "a blank user cannot be sent");
    }

    function test_bluetooth_passkey_takes_six_visible_digits() {
        const t = make({ icon: "bluetooth", message: "Clave de «Teclado»", reveal: true, digits: true, maxLength: 6,
            passwordLabel: "Clave" });
        tryVerify(() => t.field.activeFocus);
        compare(t.field.echoMode, TextInput.Normal);
        type("12a34567");
        compare(t.field.text, "123456");
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "123456", false]]);
    }

    function test_bluetooth_confirmation_shows_the_code() {
        const t = make({ kind: "confirm", icon: "bluetooth", message: "¿Emparejar con «ZON»?", code: "012345",
            continueLabel: "Emparejar" });
        const code = findChild(t.dialog, "code");
        verify(code.visible);
        compare(code.text, "012345");
        verify(!t.field.visible);
        tryVerify(() => findChild(t.dialog, "continue").activeFocus);
        keyClick(Qt.Key_Return);
        compare(t.dialog.answers, [[true, "", false]]);
    }

    function test_display_code_only_offers_cancel() {
        const t = make({ kind: "display", icon: "bluetooth", message: "Escribe este código en «Teclado»", code: "987654" });
        verify(!findChild(t.dialog, "continue").visible);
        verify(t.dialog.isDisplay && !t.dialog.canContinue);
        tryVerify(() => findChild(t.dialog, "cancel").activeFocus);
        t.dialog.accept();
        compare(t.dialog.answers.length, 0);
        keyClick(Qt.Key_Escape);
        compare(t.dialog.answers, [[false, "", false]]);
    }
}
