pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A margin note: a small kanji mark and a spaced label above free content,
// no card around it. Notes are separated by space, not by boxes.
ColumnLayout {
    id: note
    property string mark
    property string label
    default property alias content: body.data
    spacing: CortetsuDesign.spacingCompact

    RowLayout {
        spacing: CortetsuDesign.spacingCompact
        Text {
            text: note.mark
            visible: note.mark !== ""
            font.family: CortetsuTypography.kanjiFamily
            font.pixelSize: CortetsuTypography.labelLargePx
            color: CortetsuDesign.colorIndicator
            opacity: 0.85
        }
        DashLabel { text: note.label }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 2
    }
}
