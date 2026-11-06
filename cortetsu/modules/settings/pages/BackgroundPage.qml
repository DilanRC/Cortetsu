pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../../../theme"
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: CortetsuDesign.spacingSection
    WallpaperSection { context: root.context }
}
