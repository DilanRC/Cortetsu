import QtQuick
import QtTest
import "../../../modules"

TestCase {
    id: testCase
    name: "BottomHubTraySegment"
    when: windowShown
    visible: true
    width: 640
    height: 480

    property var trayItems: []

    Component {
        id: trayComponent
        CortetsuTraySegment {
            items: testCase.trayItems
        }
    }

    function test_empty_visible_then_empty_again() {
        trayItems = [];
        const segment = trayComponent.createObject(testCase);
        verify(segment !== null);
        tryCompare(segment, "visible", false);
        compare(segment.width, 0);

        trayItems = [
            {
                id: "test-tray",
                title: "Test",
                iconSource: ""
            }
        ];
        tryCompare(segment, "visible", true);
        tryVerify(() => segment.width > 0);

        trayItems = [];
        tryCompare(segment, "visible", false);
        tryCompare(segment, "width", 0);
        segment.destroy();
    }

    function test_attention_state_has_discreet_indicator_only_when_requested() {
        trayItems = [
            { key: "active", id: "same-app", title: "Active", iconSource: "", needsAttention: false },
            { key: "attention", id: "same-app", title: "Attention", iconSource: "", needsAttention: true }
        ];
        const segment = trayComponent.createObject(testCase);
        verify(segment !== null);
        tryVerify(() => findChild(segment, "tray-attention-attention-indicator") !== null);
        tryVerify(() => findChild(segment, "tray-attention-attention-indicator")?.visible ?? false);
        verify(!(findChild(segment, "tray-active-attention-indicator")?.visible ?? false));
        segment.destroy();
    }
}
