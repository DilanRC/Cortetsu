pragma ComponentBehavior: Bound

import QtQuick.Layouts
import qs.modules
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Clock")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            checked: CortetsuConfig.bar.clock.background
            onToggled: CortetsuConfig.bar.clock.background = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Show icon")
            checked: CortetsuConfig.bar.clock.showIcon
            onToggled: CortetsuConfig.bar.clock.showIcon = checked
        }
    }
}
