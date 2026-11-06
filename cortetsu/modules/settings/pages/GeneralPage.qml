pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: 32
    AudioSection { context: root.context }
    PowerSection { context: root.context }
    InputSection { context: root.context }
}
