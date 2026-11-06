pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../../../theme"
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: CortetsuDesign.spacingSection
    AppearanceSection { context: root.context }
}
