import QtQuick
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property string mode
    required property var popouts

    implicitWidth: loader.implicitWidth + CortetsuDesign.spacingStandard * 2
    implicitHeight: loader.implicitHeight + CortetsuDesign.spacingStandard * 2

    // The loaded popup owns the only painted surface. This item only keeps
    // detached geometry and input containment stable around it.

    // Keep clicks inside the detached surface from reaching the application below.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        z: -1
    }

    Loader {
        id: loader
        anchors.centerIn: parent
        sourceComponent: {
            switch (root.mode) {
            case "audio": return audio;
            case "network": return network;
            case "bluetooth": return bluetooth;
            case "battery": return battery;
            case "kblayout": return keyboard;
            case "lockstatus": return lockstatus;
            default: return empty;
            }
        }
    }

    Component { id: audio; CortetsuAudioPopup { popouts: root.popouts } }
    Component { id: network; CortetsuNetworkPopup { popouts: root.popouts } }
    Component { id: bluetooth; CortetsuBluetoothPopup { popouts: root.popouts } }
    Component { id: battery; CortetsuBatteryPopup {} }
    Component { id: keyboard; CortetsuKeyboardPopup {} }
    Component { id: lockstatus; CortetsuLockStatusPopup {} }
    Component { id: empty; CortetsuText { text: qsTr("Surface unavailable"); textSize: CortetsuDesign.bodyPx } }
}
