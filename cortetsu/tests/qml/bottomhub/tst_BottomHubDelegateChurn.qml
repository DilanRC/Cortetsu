import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "BottomHubDelegateChurn"
    when: windowShown
    visible: true
    width: 640
    height: 480

    Component {
        id: directArrayComponent

        Item {
            id: host
            property var values: []
            property int created: 0
            property int destroyed: 0

            Repeater {
                model: host.values
                delegate: Item {
                    required property var modelData
                    objectName: `key-${modelData.key}`
                    Component.onCompleted: host.created += 1
                    Component.onDestruction: host.destroyed += 1
                }
            }
        }
    }

    function test_direct_array_recreates_every_delegate_when_active_state_changes() {
        const host = directArrayComponent.createObject(testCase, {
            values: [
                { key: "one", active: false },
                { key: "two", active: false }
            ]
        });
        verify(host !== null);
        tryCompare(host, "created", 2);
        const original = findChild(host, "key-one");

        host.values = [
            { key: "one", active: true },
            { key: "two", active: false }
        ];
        tryCompare(host, "created", 4);
        tryCompare(host, "destroyed", 2);
        verify(findChild(host, "key-one") !== original);
        host.destroy();
    }
}
