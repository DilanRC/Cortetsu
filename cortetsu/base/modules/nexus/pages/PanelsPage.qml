import QtQuick.Layouts
import qs.modules
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Panels")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        NavRow {
            first: true
            icon: "dashboard"
            text: qsTr("Dashboard")
            subtext: CortetsuConfig.dashboard.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "dock_to_bottom"
            text: qsTr("Taskbar")
            subtext: CortetsuConfig.bar.showOnHover ? qsTr("Reveal on hover") : qsTr("Reveal on drag")
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "apps"
            text: qsTr("Launcher")
            subtext: CortetsuConfig.launcher.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "dock_to_right"
            text: qsTr("Sidebar")
            subtext: CortetsuConfig.sidebar.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            last: true
            icon: "construction"
            text: qsTr("Utilities")
            subtext: CortetsuConfig.utilities.enabled ? qsTr("Enabled") : qsTr("Disabled")
            onClicked: root.nState.openSubPage(5)
        }
    }
}
