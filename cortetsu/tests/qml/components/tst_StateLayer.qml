import QtQuick
import QtTest
import "../../../components"
import "../../../modules" as Legacy

TestCase {
    id: testCase
    name: "StateLayer"
    when: windowShown
    visible: true
    width: 380
    height: 160

    Component {
        id: nativeFixture
        CortetsuStateLayer { manualPressOverride: true }
    }
    Component {
        id: legacyFixture
        Legacy.CortetsuStateLayer { manualPressOverride: true }
    }

    function test_module_adapter_preserves_stronger_press_feedback() {
        const a = createTemporaryObject(nativeFixture, testCase);
        const b = createTemporaryObject(legacyFixture, testCase);
        fuzzyCompare(a.stateOpacity, 0.08, 0.0001);
        fuzzyCompare(b.stateOpacity, 0.16, 0.0001);
        a.manualPressOverride = false;
        b.manualPressOverride = false;
        a.manualHoverOverride = true;
        b.manualHoverOverride = true;
        fuzzyCompare(a.stateOpacity, 0.08, 0.0001);
        fuzzyCompare(b.stateOpacity, 0.08, 0.0001);
    }

    function test_disabled_or_suppressed_overlays_dont_paint() {
        const a = createTemporaryObject(nativeFixture, testCase);
        const b = createTemporaryObject(legacyFixture, testCase);
        a.disabled = true;
        b.disabled = true;
        compare(a.stateOpacity, 0);
        compare(b.stateOpacity, 0);
        a.disabled = false;
        b.disabled = false;
        a.showHoverBackground = false;
        b.showHoverBackground = false;
        compare(a.stateOpacity, 0);
        compare(b.stateOpacity, 0);
    }

    function test_public_color_and_radius_survive_compatibility() {
        const item = createTemporaryObject(legacyFixture, testCase);
        item.radius = 8;
        item.color = "red";
        compare(item.rect.radius, 8);
        compare(item.radius, 8);
        compare(item.rect.color, "#ff0000");
    }
}
