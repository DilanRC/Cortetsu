pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.settings as Settings
import qs.modules.nexus.common

PageBase {
    id: root
    title: qsTr("Conexiones")
    isSubPage: true
    Settings.NetworkPage {
        width: root.cappedWidth
        anchors.horizontalCenter: parent.horizontalCenter
        screen: root.nState.screen
        screenState: null
    }
}
