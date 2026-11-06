pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../../../theme"
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: CortetsuDesign.spacingSection
    AudioSection { context: root.context }
    PowerSection { context: root.context }
    InputSection { context: root.context }
}
