pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.modules.nexus

ColumnLayout {
    id: root
    required property NexusState nState
    property int limit: 0
    property bool enableFilter: false
    signal networkSelected(var network)
    Repeater {
        model: root.limit > 0 ? Connectivity.wifi.networks.slice(0, root.limit) : Connectivity.wifi.networks
        delegate: CortetsuListRow {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.name
            subtitle: modelData.connected ? Connectivity.internetLabel : modelData.known ? qsTr("Guardada") : qsTr("Disponible")
            icon: "wifi"
            onClicked: root.networkSelected(modelData)
        }
    }
}
