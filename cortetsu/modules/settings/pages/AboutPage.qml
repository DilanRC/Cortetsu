pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../sections"

ColumnLayout {
    id: root
    required property var context
    AboutSection { context: root.context }
}
