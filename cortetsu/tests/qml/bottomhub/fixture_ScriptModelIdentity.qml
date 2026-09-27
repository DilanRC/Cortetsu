import QtQuick
import Quickshell

ShellRoot {
    Item {
        id: host
        property var values: [
            { key: "one", active: false, windowCount: 1 },
            { key: "two", active: false, windowCount: 1 }
        ]
        property int created: 0
        property int destroyed: 0

        Repeater {
            id: delegates
            model: ScriptModel {
                values: host.values
                objectProp: "key"
            }

            Item {
                required property var modelData
                objectName: modelData.key
                Component.onCompleted: host.created += 1
                Component.onDestruction: host.destroyed += 1
            }
        }

        Timer {
            interval: 50
            running: true
            onTriggered: {
                host.values = [
                    { key: "one", active: true, windowCount: 2 },
                    { key: "two", active: false, windowCount: 1 }
                ];
                Qt.callLater(() => {
                    const current = delegates.itemAt(0);
                    if (host.created === 2 && host.destroyed === 0
                            && current.modelData.active
                            && current.modelData.windowCount === 2)
                        console.log("SCRIPT_MODEL_IDENTITY_PASS created=2 destroyed=0 data=updated");
                    else
                        console.error(`SCRIPT_MODEL_IDENTITY_FAIL created=${host.created} destroyed=${host.destroyed}`);
                    Qt.quit();
                });
            }
        }
    }
}
