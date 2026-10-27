import QtQuick
import QtTest
import "../../../components"
import "../../../theme"

// Phase-1 motion contract: Emil-style curves, Reduced motion zeroing every
// duration, the shared 0.97 press, contrast-safe indicators and tooltips
// that open at once while another one is warm.
TestCase {
    id: testCase
    name: "MotionTokens"
    when: windowShown
    visible: true
    width: 480
    height: 240

    Component {
        id: buttonFixture
        CortetsuButton { label: "Guardar" }
    }

    Component {
        id: tooltipPair
        Item {
            width: 300
            height: 80
            property alias first: first
            property alias second: second
            Item { id: a; width: 40; height: 40 }
            Item { id: b; x: 100; width: 40; height: 40 }
            CortetsuTooltip { id: first; target: a; text: "Primero" }
            CortetsuTooltip { id: second; target: b; text: "Segundo" }
        }
    }

    function cleanup() {
        CortetsuDesign.reducedMotion = false;
        CortetsuDesign.scheme = ({});
        CortetsuDesign.tooltipWarmUntil = 0;
    }

    function test_curves_are_bezier_splines_ending_at_one() {
        for (const curve of [CortetsuDesign.easeOut, CortetsuDesign.easeInOut, CortetsuDesign.easeDrawer]) {
            compare(curve.length, 6);
            compare(curve[4], 1);
            compare(curve[5], 1);
        }
        compare(CortetsuDesign.easeOut[0], 0.23);
        compare(CortetsuDesign.easeDrawer[1], 0.72);
    }

    function test_exits_are_shorter_and_budgets_hold() {
        verify(CortetsuDesign.motionPopoverExitMs < CortetsuDesign.motionPopoverMs);
        verify(CortetsuDesign.motionPanelExitMs < CortetsuDesign.motionPanelMs);
        verify(CortetsuDesign.motionPopoverMs <= 300);
        verify(CortetsuDesign.motionDrawerMs <= 500);
        verify(CortetsuDesign.pressScale >= 0.95 && CortetsuDesign.pressScale < 1);
    }

    function test_reduced_motion_zeroes_durations_but_not_intent_delay() {
        const delay = CortetsuDesign.tooltipDelayMs;
        CortetsuDesign.reducedMotion = true;
        for (const name of ["motionInstantMs", "motionFastMs", "motionStandardMs", "motionDeliberateMs",
                "motionPanelMs", "motionDrawerMs", "motionTooltipMs", "motionPopoverMs",
                "motionPopoverExitMs", "motionPanelExitMs", "wallUtilityPanelMotionMs"])
            compare(CortetsuDesign[name], 0, name);
        compare(CortetsuDesign.tooltipDelayMs, delay);
        CortetsuDesign.reducedMotion = false;
        compare(CortetsuDesign.motionFastMs, 120);
    }

    function test_indicator_reaches_three_to_one() {
        const surfaces = [CortetsuDesign.colorTetsu, CortetsuDesign.colorSurfaceHigh];
        for (const s of surfaces)
            verify(CortetsuDesign.contrast(CortetsuDesign.colorIndicator, s) >= 3, "default");
        // A scheme whose primary is as dark as the bundled indigo is lifted.
        CortetsuDesign.scheme = ({ primary: "334e68" });
        for (const s of surfaces)
            verify(CortetsuDesign.contrast(CortetsuDesign.colorIndicator, s) >= 3, "scheme");
    }

    function test_button_press_uses_shared_scale() {
        const button = createTemporaryObject(buttonFixture, testCase);
        mousePress(button);
        tryCompare(button, "visualScale", CortetsuDesign.pressScale, 1000);
        mouseRelease(button);
        tryVerify(() => button.visualScale > CortetsuDesign.pressScale, 1000);
    }

    function test_second_tooltip_skips_the_delay() {
        const pair = createTemporaryObject(tooltipPair, testCase);
        pair.first.hovered = true;
        verify(!pair.first.visible, "first tooltip waits for its delay");
        tryCompare(pair.first, "visible", true, CortetsuDesign.tooltipDelayMs * 4);
        // Moving to the neighbour: the first closes, the second opens at once.
        pair.first.hovered = false;
        pair.second.hovered = true;
        compare(pair.second.visible, true);
        compare(pair.second.warm, true);
        // The exit fade is shorter than the entry; the popup is gone after it.
        pair.second.hovered = false;
        tryCompare(pair.second, "visible", false, CortetsuDesign.motionPopoverMs * 4);
    }

    function test_cold_tooltip_waits_again() {
        const pair = createTemporaryObject(tooltipPair, testCase);
        CortetsuDesign.tooltipWarmUntil = Date.now() - 1;
        pair.second.hovered = true;
        verify(!pair.second.visible);
        compare(pair.second.warm, false);
    }
}
