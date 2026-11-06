pragma ComponentBehavior: Bound

import QtQuick.Layouts
import ".."
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: 32
    NetworkPage { context: root.context }
    BluetoothSection { context: root.context }
    AutomationSection { context: root.context }
}
