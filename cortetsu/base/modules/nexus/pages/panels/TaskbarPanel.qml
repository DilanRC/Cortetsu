pragma ComponentBehavior: Bound

import QtQuick.Layouts
import qs.modules
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Taskbar")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the bar when the cursor reaches the screen edge")
            checked: CortetsuConfig.bar.showOnHover
            onToggled: CortetsuConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            value: CortetsuConfig.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => CortetsuConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: qsTr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: qsTr("Workspaces")
            subtext: qsTr("Indicators, window icons")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: qsTr("Active window")
            subtext: qsTr("Title display, popout")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: qsTr("Tray")
            subtext: qsTr("System tray icons")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: qsTr("Status icons")
            subtext: qsTr("Visible indicators")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: qsTr("Clock")
            subtext: qsTr("Date, icon, background")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            first: true
            text: qsTr("Volume")
            subtext: qsTr("Scroll on the top half of the bar to adjust volume")
            checked: CortetsuConfig.bar.scrollActions.volume
            onToggled: CortetsuConfig.bar.scrollActions.volume = checked
        }

    }
}
