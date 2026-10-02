pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.components
import qs.services
import qs.modules.nexus

ColumnLayout {
    required property NexusState nState
    required property int cappedWidth
    Repeater {
        model: Connectivity.wifi.devices.filter(device => device.type === DeviceType.Wired)
        delegate: CortetsuListRow {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.name
            subtitle: modelData.connected ? Connectivity.internetLabel : qsTr("Cable desconectado")
            icon: "cable"
            onClicked: Connectivity.wifi.refreshDetails(modelData.name)
        }
    }
}
