pragma ComponentBehavior: Bound

import QtQuick.Layouts
import qs.modules
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Tray")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            checked: CortetsuConfig.bar.tray.background
            onToggled: CortetsuConfig.bar.tray.background = checked
        }

        ToggleRow {
            text: qsTr("Recolour icons")
            checked: CortetsuConfig.bar.tray.recolour
            onToggled: CortetsuConfig.bar.tray.recolour = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Popout on hover")
            subtext: qsTr("Show the tray menu popout when hovering")
            checked: CortetsuConfig.bar.popouts.tray
            onToggled: CortetsuConfig.bar.popouts.tray = checked
        }
    }
}
