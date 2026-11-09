pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import ".."
import "../controls"

// A category's own page, as on Windows 11: one row per subpage with what it
// holds and how it stands. Settings themselves live one level down.
SettingsPage {
    id: root

    required property var context
    required property var controller
    readonly property var category: controller.selectedCategory

    SettingsGroup {
        Repeater {
            model: root.category?.pages ?? []

            SettingNavRow {
                required property var modelData
                objectName: `subpage-${modelData.id}`
                title: modelData.title
                detail: modelData.detail
                icon: modelData.icon
                value: root.context.pageSummary(modelData.id)
                alertText: root.context.pageAlert(modelData.id)
                onActivated: root.controller.select(modelData.id)
            }
        }
    }
}
