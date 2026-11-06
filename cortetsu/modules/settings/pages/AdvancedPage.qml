pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: 32
    DisplaySection { context: root.context }
    ShortcutsSection { objectName: "shortcutsSection"; context: root.context }
}
