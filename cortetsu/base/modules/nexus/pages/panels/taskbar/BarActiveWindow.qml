pragma ComponentBehavior: Bound

import QtQuick.Layouts
import qs.modules
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Active window")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Inverted")
            checked: CortetsuConfig.bar.activeWindow.inverted
            onToggled: CortetsuConfig.bar.activeWindow.inverted = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Only show the active window title while hovering")
            checked: CortetsuConfig.bar.activeWindow.showOnHover
            onToggled: CortetsuConfig.bar.activeWindow.showOnHover = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show a window details popout when hovering")
            checked: CortetsuConfig.bar.popouts.activeWindow
            onToggled: CortetsuConfig.bar.popouts.activeWindow = checked
        }
    }
}
