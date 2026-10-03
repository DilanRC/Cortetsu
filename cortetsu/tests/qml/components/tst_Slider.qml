import QtQuick
import QtTest
import "../../../components"

// The slider reports what the user asked for and shows what the backend
// holds. It must not overwrite `value`, or the caller's binding dies on the
// first drag and later backend changes stop reaching the handle.
TestCase {
    id: testCase
    name: "Slider"
    when: windowShown
    visible: true
    width: 400
    height: 100

    QtObject {
        id: backend
        property real level: 0.25
        property bool accepts: true
    }

    Component {
        id: bound
        CortetsuSlider {
            width: 200
            value: backend.level
            onMoved: next => { if (backend.accepts) backend.level = next; }
        }
    }

    SignalSpy { id: moved; signalName: "moved" }

    function init() { backend.level = 0.25; backend.accepts = true; }

    function test_a_drag_keeps_the_binding_alive() {
        const slider = createTemporaryObject(bound, testCase);
        mouseClick(slider, 150, slider.height / 2);
        fuzzyCompare(backend.level, 0.75, 0.01);
        backend.level = 0.1;
        compare(slider.value, 0.1);
        fuzzyCompare(slider.progress, 0.1, 0.001);
    }

    function test_a_rejected_change_leaves_the_real_value_on_screen() {
        const slider = createTemporaryObject(bound, testCase);
        backend.accepts = false;
        mouseClick(slider, 180, slider.height / 2);
        compare(backend.level, 0.25);
        fuzzyCompare(slider.progress, 0.25, 0.001);
    }

    function test_keys_request_a_step_and_clamp_to_the_range() {
        const slider = createTemporaryObject(bound, testCase);
        moved.target = slider;
        moved.clear();
        slider.forceActiveFocus();
        keyClick(Qt.Key_Right);
        fuzzyCompare(backend.level, 0.30, 0.001);
        keyClick(Qt.Key_End);
        compare(backend.level, 1);
        keyClick(Qt.Key_Right);
        compare(backend.level, 1);
        keyClick(Qt.Key_Home);
        compare(backend.level, 0);
        compare(moved.count, 4);
    }

    function test_the_handle_follows_the_pointer_while_pressed() {
        const slider = createTemporaryObject(bound, testCase);
        backend.accepts = false;
        mousePress(slider, 100, slider.height / 2);
        verify(slider.dragging);
        fuzzyCompare(slider.progress, 0.5, 0.01);
        mouseRelease(slider, 100, slider.height / 2);
        fuzzyCompare(slider.progress, 0.25, 0.001);
    }
}
