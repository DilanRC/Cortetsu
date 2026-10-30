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

// A few lines of synced lyrics around the one being sung, centred: the
// sung line in ink, its neighbours fading by distance. All lines share one
// size, so the block never changes height while the song plays.
ColumnLayout {
    id: root
    property int before: 1
    property int after: 2
    spacing: CortetsuDesign.spacingCompact

    Repeater {
        model: root.before + 1 + root.after

        DashInk {
            id: line
            required property int index
            readonly property int offset: index - root.before
            readonly property int at: Lyrics.index + offset
            readonly property bool sung: offset === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: at >= 0 && at < Lyrics.lines.length ? (Lyrics.lines[at].text || "♪") : " "
            textFormat: Text.PlainText
            textSize: CortetsuTypography.inkLinePx
            font.italic: !sung
            font.weight: sung ? Font.Normal : Font.Light
            color: sung ? CortetsuDesign.colorWashi : CortetsuDesign.colorOnSurfaceVariant
            opacity: sung ? 1 : Math.max(0.2, 0.7 - Math.abs(offset) * 0.22)
            elide: Text.ElideRight
        }
    }
}
