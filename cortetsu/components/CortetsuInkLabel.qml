import QtQuick
import QtQuick.Layouts
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

// The label of a group in the ink language: a small kanji mark and a spaced
// caps title, no box. It is the same label the dashboard puts over its
// margin notes, so groups read the same on every surface.
RowLayout {
    id: root
    property string title
    property string mark
    spacing: CortetsuDesign.spacingCompact

    Text {
        visible: root.mark !== ""
        text: root.mark
        font.family: CortetsuDesign.fontKanji
        font.pixelSize: CortetsuTypography.labelLargePx
        color: CortetsuDesign.colorIndicator
        opacity: 0.85
    }
    CortetsuText {
        text: root.title.toUpperCase()
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }
}
