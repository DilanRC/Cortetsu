import QtQuick
import QtTest
import "../../../modules/hardware/KeyCapture.js" as KeyCapture

TestCase {
    name: "KeyCapture"

    function test_modifier_only_keeps_listening() {
        const result = KeyCapture.resolve(Qt.Key_Meta, Qt.MetaModifier | Qt.ShiftModifier);
        compare(result.kind, "modifier");
        compare(result.held, ["SHIFT", "SUPER"]);
        compare(result.chord, "");
    }

    function test_complete_chord_uses_hyprland_order() {
        const result = KeyCapture.resolve(Qt.Key_K, Qt.MetaModifier | Qt.ShiftModifier | Qt.ControlModifier);
        compare(result.kind, "chord");
        compare(result.chord, "CTRL + SHIFT + SUPER + K");
    }

    function test_plain_key_is_rejected() {
        compare(KeyCapture.resolve(Qt.Key_A, Qt.NoModifier).kind, "bare");
        compare(KeyCapture.resolve(Qt.Key_1, Qt.NoModifier).kind, "bare");
        compare(KeyCapture.resolve(Qt.Key_Return, Qt.NoModifier).kind, "bare");
    }

    function test_function_and_print_keys_need_no_modifier() {
        compare(KeyCapture.resolve(Qt.Key_F9, Qt.NoModifier).chord, "F9");
        compare(KeyCapture.resolve(Qt.Key_F12, Qt.AltModifier).chord, "ALT + F12");
        compare(KeyCapture.resolve(Qt.Key_Print, Qt.NoModifier).chord, "Print");
    }

    function test_unnamed_key_is_reported_not_dropped() {
        compare(KeyCapture.resolve(Qt.Key_Exclam, Qt.ShiftModifier).kind, "unsupported");
        compare(KeyCapture.resolve(Qt.Key_MediaPlay, Qt.NoModifier).kind, "unsupported");
    }

    function test_parts_split_a_stored_chord() {
        compare(KeyCapture.parts("SUPER + SHIFT + D"), ["SUPER", "SHIFT", "D"]);
        compare(KeyCapture.parts(""), []);
    }
}
