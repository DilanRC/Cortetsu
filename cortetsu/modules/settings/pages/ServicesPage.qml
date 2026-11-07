pragma ComponentBehavior: Bound

import QtQuick.Layouts
import "../../../theme"
import ".."
import "../sections"

ColumnLayout {
    id: root
    required property var context
    spacing: CortetsuDesign.spacingSection
    NetworkPage { context: root.context }
    BluetoothSection { context: root.context }
    AutomationSection { context: root.context }
    WeatherSection {}
    RecorderSection {}
}
