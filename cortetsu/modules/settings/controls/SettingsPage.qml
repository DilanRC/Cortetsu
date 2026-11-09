pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"

// The one container every Settings page sits in. A page says what kind it
// is and the container decides its width: a form keeps a readable column,
// a gallery or a two-column page may take more. The column is centred in
// the room the window leaves, so the space beside it is shared equally
// instead of piling up on one side.
Item {
    id: root

    // "form": rows of label and control. "wide": galleries, grids and pages
    // that split into two columns when there is room.
    property string kind: "form"
    readonly property real maxWidth: kind === "wide" ? 1120 : 780
    readonly property real columnWidth: Math.min(width, maxWidth)
    readonly property real columnX: Math.round((width - columnWidth) / 2)
    default property alias content: column.data

    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        x: root.columnX
        width: root.columnWidth
        spacing: CortetsuDesign.spacingSection
    }
}
