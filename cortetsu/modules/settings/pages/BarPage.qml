pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: 32
    BottomHubSection { context: root.context }
}
