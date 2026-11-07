import QtQuick
import QtTest
import "../../../modules"

TestCase {
    name: "BottomHubAutoHide"
    when: windowShown
    visible: true
    width: 120
    height: 80

    property int enteredCount: 0
    property int exitedCount: 0

    CortetsuBottomHubVisibility {
        id: visibility
        hideDelayMs: 40
    }

    CortetsuBottomHubHoverTarget {
        id: target
        width: 60
        height: 60
        enabled: visibility.autoHideEnabled
        onPointerEntered: {
            enteredCount++;
            visibility.pointerEntered();
        }
        onPointerExited: {
            exitedCount++;
            visibility.pointerExited();
        }
    }

    function init(): void {
        visibility.autoHideEnabled = false;
        visibility.setShown(true);
        visibility.hoverCount = 0;
        enteredCount = 0;
        exitedCount = 0;
    }

    function test_pointer_entry_reveals_and_exit_hides_after_delay(): void {
        visibility.autoHideEnabled = true;
        visibility.setShown(false);

        visibility.pointerEntered();
        verify(visibility.shown, "entering the reveal target shows the hub");
        wait(60);
        verify(visibility.shown, "the hub stays visible while the pointer is inside");

        visibility.pointerExited();
        tryVerify(() => !visibility.shown, 500);
    }

    function test_manual_show_cancels_hover_hide(): void {
        visibility.autoHideEnabled = true;
        visibility.pointerEntered();
        visibility.pointerExited();
        visibility.setShown(true);
        wait(80);
        verify(visibility.shown, "an explicit show remains visible after the hover delay");
    }

    function test_disabling_auto_hide_restores_hub(): void {
        visibility.autoHideEnabled = true;
        visibility.setShown(false);
        visibility.autoHideEnabled = false;
        verify(visibility.shown, "turning auto-hide off restores the always-visible hub");
        compare(visibility.hoverCount, 0, "disabling clears stale per-monitor hover state");
    }

    function test_hover_target_reports_real_pointer_transitions(): void {
        visibility.setShown(false);
        visibility.autoHideEnabled = true;
        mouseMove(target, 20, 20);
        tryVerify(() => enteredCount === 1, 500);
        verify(visibility.shown, "the hover target is connected to the visibility controller");
        mouseMove(this, 100, 70);
        tryVerify(() => exitedCount === 1, 500);
        tryVerify(() => !visibility.shown, 500);
    }
}
