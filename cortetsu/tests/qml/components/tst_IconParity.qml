import QtQuick
import QtTest
import "../../../components" as Native
import "../../../modules" as Compat

TestCase {
    id: testCase
    name: "IconParity"
    when: windowShown
    visible: true
    width: 400
    height: 160

    Component {
        id: iconNative
        Native.CortetsuIcon { text: "wifi"; iconSize: 24 }
    }
    Component {
        id: iconCompat
        Compat.CortetsuIcon { text: "wifi"; iconSize: 24 }
    }

    function test_module_alias_keeps_core_font_and_text_contract() {
        const native = createTemporaryObject(iconNative, testCase);
        const compat = createTemporaryObject(iconCompat, testCase);
        compare(native.text, compat.text);
        compare(native.iconSize, compat.iconSize);
        compare(native.font.family, compat.font.family);
        compare(native.font.pixelSize, compat.font.pixelSize);
        compare(native.renderType, compat.renderType);
        compare(native.color, compat.color);
    }

    function test_shared_icon_parameters_remain_mutable() {
        const native = createTemporaryObject(iconNative, testCase);
        const compat = createTemporaryObject(iconCompat, testCase);
        native.iconSize = 32;
        compat.iconSize = 32;
        native.fill = 1;
        compat.fill = 1;
        native.grade = 50;
        compat.grade = 50;
        compare(native.font.pixelSize, compat.font.pixelSize);
        compare(native.fill, compat.fill);
        compare(native.grade, compat.grade);
        compat.text = "bluetooth";
        compare(compat.text, "bluetooth");
    }
}
