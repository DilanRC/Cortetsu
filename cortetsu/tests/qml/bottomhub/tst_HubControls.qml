import QtQuick
import QtTest
import "../../../modules"
import "../../../theme"

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
            displayType: 0
            occupiedWorkspaceIds: []
            appIconSources: ({})
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

    function test_number_mode_replaces_graphic_workspace_markers() {
        const dots = createTemporaryObject(dotsComponent, testCase, { displayType: 1 });
        const number = find(dots, c => c.objectName === "workspace-number-1");
        const shape = find(dots, c => c.objectName === "workspace-shape-1");
        verify(number !== null);
        verify(shape !== null);
        verify(number.visible);
        verify(!shape.visible);
    }

    function test_app_icons_only_replace_markers_for_occupied_workspaces() {
        const dots = createTemporaryObject(dotsComponent, testCase, {
            showAppIcons: true,
            occupiedWorkspaceIds: [2],
            appIconSources: ({"2": Qt.resolvedUrl("../../../../cortetsu/assets/branding/cortetsu-mark.svg")})
        });
        const emptyIcon = find(dots, c => c.objectName === "workspace-app-icon-1");
        const occupiedIcon = find(dots, c => c.objectName === "workspace-app-icon-2");
        const occupiedShape = find(dots, c => c.objectName === "workspace-shape-2");
        verify(emptyIcon !== null && !emptyIcon.visible);
        verify(occupiedIcon !== null && occupiedIcon.visible);
        verify(occupiedShape.visible);
    }

    function test_workspace_numbers_take_priority_over_app_icons() {
        const dots = createTemporaryObject(dotsComponent, testCase, {
            displayType: 1,
            showAppIcons: true,
            occupiedWorkspaceIds: [1],
            appIconSources: ({"1": Qt.resolvedUrl("../../../../cortetsu/assets/branding/cortetsu-mark.svg")})
        });
        const number = find(dots, c => c.objectName === "workspace-number-1");
        const icon = find(dots, c => c.objectName === "workspace-app-icon-1");
        verify(number.visible);
        verify(!icon.visible);
    }

    function test_workspace_app_icons_can_be_colored_with_the_active_theme() {
        const dots = createTemporaryObject(dotsComponent, testCase, {
            showAppIcons: true,
            monochromeAppIcons: true,
            occupiedWorkspaceIds: [1],
            appIconSources: ({"1": Qt.resolvedUrl("../../../../cortetsu/assets/branding/cortetsu-mark.svg")})
        });
        const icon = find(dots, c => c.objectName === "workspace-app-icon-1");
        verify(icon !== null && icon.visible);
        verify(icon.layer.enabled, "the workspace icon layer should apply monochrome styling");
        compare(dots.appIconTint, CortetsuDesign.colorWashi);
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
