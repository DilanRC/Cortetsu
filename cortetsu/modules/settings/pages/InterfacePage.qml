pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../../../theme"
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: CortetsuDesign.spacingSection
    DesktopSection { context: root.context }
    LauncherSection { context: root.context }
    NotificationsSection { context: root.context }
}
