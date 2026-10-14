import QtQuick
import QtTest
import "../../../components"

TestCase {
    id: testCase
    name: "ProgressBar"
    when: windowShown
    visible: true
    width: 600
    height: 100

    Component {
        id: bar
        CortetsuProgressBar { width: 400; value: 0.5; motionDuration: 400 }
    }

    function test_resizing_moves_the_fill_at_once() {
        const item = createTemporaryObject(bar, testCase);
        const fill = findChild(item, "fill");
        tryCompare(fill, "width", 200);
        item.width = 100;
        compare(fill.width, 50);
        verify(fill.width <= item.width);
    }

    function test_a_new_value_animates_to_its_fraction() {
        const item = createTemporaryObject(bar, testCase);
        const fill = findChild(item, "fill");
        tryCompare(fill, "width", 200);
        item.value = 1;
        verify(fill.width < 400, "the fill travels instead of jumping");
        tryCompare(fill, "width", 400);
    }

    function test_out_of_range_values_are_clamped() {
        const item = createTemporaryObject(bar, testCase, { value: 7 });
        tryCompare(findChild(item, "fill"), "width", 400);
        item.value = -1;
        verify(!item.visible, "an unavailable reading hides the bar");
    }
}
