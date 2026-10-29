import QtQuick
import QtTest
import "../../../modules"

TestCase {
    id: testCase
    name: "BottomHubControls"
    when: windowShown
    visible: true
    width: 640
    height: 480

    Component {
        id: dotsComponent
        CortetsuWorkspaceDots {
            workspaceCount: 3
            workspaceOffset: 0
            activeWsId: 1
            occupiedWorkspaceIds: []
        }
    }

    Component {
        id: pillComponent
        StatusPill {}
    }

    SignalSpy {
        id: requested
        signalName: "workspaceRequested"
    }

    function find(item, test) {
        if (test(item))
            return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) {
            const hit = find(kids[i], test);
            if (hit)
                return hit;
        }
        return null;
    }

    function test_the_gap_between_two_dots_still_picks_a_workspace() {
        const dots = createTemporaryObject(dotsComponent, testCase);
        requested.target = dots;
        requested.clear();
        const second = find(dots, c => c.objectName === "workspace-2");
        verify(second !== null);
        verify(second.height >= 36, `dot target is ${second.height} px tall`);
        // One pixel left of the second dot, inside the gap after the first.
        const gap = dots.mapFromItem(second, -1, second.height / 2);
        mouseClick(dots, gap.x, gap.y);
        compare(requested.count, 1);
        compare(requested.signalArguments[0][0], 2);
    }

    function test_status_items_are_full_height_targets() {
        const pill = createTemporaryObject(pillComponent, testCase, { recordingActive: true, dndActive: true });
        const item = find(pill, c => c.pulse !== undefined && c.visible && c.label === "DND");
        verify(item !== null);
        verify(item.implicitHeight >= 36, `status item is ${item.implicitHeight} px tall`);
    }

    function test_the_recording_dot_is_opaque_again_when_recording_stops() {
        const pill = createTemporaryObject(pillComponent, testCase, { recordingActive: true });
        const dot = find(pill, c => c.text === "fiber_manual_record");
        verify(dot !== null);
        compare(dot.scale, 1);
        tryVerify(() => dot.opacity < 0.95, 2000);
        pill.recordingActive = false;
        tryCompare(dot, "opacity", 1, 500);
    }
}
