pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Two columns of groups side by side when the page is wide enough for two
// readable columns, one above the other otherwise. Groups are placed by the
// page, so related ones stay together whichever way it flows.
GridLayout {
    id: root

    default property alias content: leftColumn.data
    property alias aside: rightColumn.data
    readonly property bool split: width >= 900

    Layout.fillWidth: true
    columns: split ? 2 : 1
    columnSpacing: CortetsuDesign.spacingSpacious
    rowSpacing: CortetsuDesign.spacingSection

    ColumnLayout {
        id: leftColumn
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: CortetsuDesign.spacingSection
    }

    ColumnLayout {
        id: rightColumn
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: CortetsuDesign.spacingSection
    }
}
