import QtQuick
import QtTest
import "../../../modules/areapicker"

// The preview after an area capture: each button asks for one action, and a
// capture left alone is saved, never dropped.
TestCase {
    id: testCase
    name: "ScreenshotPreview"
    when: windowShown
    visible: true
    width: 500
    height: 400

    Component {
        id: previewComponent
        ScreenshotPreview {
            property var asked: []
            autoSaveMs: 150
            onCopyRequested: asked = asked.concat(["copy"])
            onSaveRequested: asked = asked.concat(["save"])
            onEditRequested: asked = asked.concat(["edit"])
            onDiscardRequested: asked = asked.concat(["discard"])
        }
    }

    function make() {
        const preview = createTemporaryObject(previewComponent, testCase, { source: "file:///nonexistent.png" });
        verify(preview);
        return preview;
    }

    function test_each_button_asks_for_its_action() {
        const preview = make();
        preview.autoSaveMs = 60000;
        for (const name of ["copy", "save", "edit", "discard"]) {
            const button = findChild(preview, name);
            verify(button, name);
            mouseClick(button);
        }
        compare(preview.asked, ["copy", "save", "edit", "discard"]);
    }

    function test_busy_blocks_buttons_and_the_timer() {
        const preview = make();
        preview.busy = true;
        mouseClick(findChild(preview, "copy"));
        wait(300);
        compare(preview.asked, []);
        preview.busy = false;
        tryCompare(preview, "asked", ["save"], 2000);
    }

    function test_left_alone_it_saves_once() {
        const preview = make();
        tryCompare(preview, "asked", ["save"], 2000);
        wait(300);
        compare(preview.asked, ["save"]);
    }

    function test_hover_holds_the_capture() {
        const preview = make();
        mouseMove(preview, 10, 10);
        wait(400);
        compare(preview.asked, []);
        mouseMove(testCase, testCase.width - 2, testCase.height - 2);
        tryCompare(preview, "asked", ["save"], 2000);
    }

    function test_new_image_restarts_the_wait() {
        const preview = make();
        preview.autoSaveMs = 400;
        wait(250);
        preview.source = "file:///nonexistent.png?v=1";
        wait(250);
        compare(preview.asked, []);
        tryCompare(preview, "asked", ["save"], 2000);
    }
}
