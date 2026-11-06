pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: 32
    DesktopSection { context: root.context }
    LauncherSection { context: root.context }
    NotificationsSection { context: root.context }
}
