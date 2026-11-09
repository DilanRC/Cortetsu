pragma ComponentBehavior: Bound

import QtQuick
import "../controls"

// "Ajustes relacionados", as Windows 11 ends a page: the pages that change
// the same thing from another side.
SettingsGroup {
    id: root

    required property var controller
    property var pages: []

    title: qsTr("Ajustes relacionados")
    icon: "link"

    Repeater {
        model: root.pages

        SettingNavRow {
            required property string modelData
            readonly property var target: root.controller.pages[modelData]
            objectName: `related-${modelData}`
            title: target.title
            detail: target.detail
            icon: target.icon
            onActivated: root.controller.select(modelData)
        }
    }
}
