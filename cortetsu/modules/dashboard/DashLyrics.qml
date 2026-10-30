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

// The lyrics of what is playing. Synced lyrics keep the sung line in the
// middle in ink and fade the rest by distance; a click on a line seeks
// there. Plain lyrics just scroll.
Item {
    id: root
    property bool large: true

    Component.onCompleted: Lyrics.consumers += 1
    Component.onDestruction: Lyrics.consumers -= 1

    readonly property bool empty: Lyrics.lines.length === 0

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width
        visible: root.empty
        spacing: CortetsuDesign.spacingCompact
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Lyrics.loading ? "詞" : "静"
            font.family: CortetsuTypography.kanjiFamily
            font.pixelSize: CortetsuTypography.inkDisplayPx
            color: CortetsuDesign.colorWashi
            opacity: 0.12
        }
        DashInk {
            Layout.alignment: Qt.AlignHCenter
            text: Lyrics.loading ? qsTr("Buscando la letra…") : qsTr("Sin letra para esta canción")
            textSize: CortetsuTypography.inkLinePx
            font.italic: true
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        visible: !root.empty
        clip: true
        model: Lyrics.lines
        currentIndex: Math.max(0, Lyrics.index)
        interactive: !Lyrics.synced
        spacing: CortetsuDesign.spacingStandard
        highlightRangeMode: Lyrics.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
        preferredHighlightBegin: height / 2 - 24
        preferredHighlightEnd: height / 2 + 24
        highlightMoveDuration: CortetsuDesign.motionDeliberateMs
        highlightFollowsCurrentItem: true
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: line
            required property var modelData
            required property int index
            readonly property int distance: Lyrics.synced && Lyrics.index >= 0 ? Math.abs(index - Lyrics.index) : 0
            readonly property bool sung: Lyrics.synced && index === Lyrics.index
            width: ListView.view.width
            height: text.implicitHeight

            DashInk {
                id: text
                width: parent.width
                text: line.modelData.text || "♪"
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                textSize: line.sung ? (root.large ? CortetsuTypography.inkTitlePx : CortetsuTypography.inkLinePx) : (root.large ? CortetsuTypography.inkLinePx : CortetsuTypography.titleSmallPx)
                font.weight: line.sung ? Font.Normal : Font.Light
                color: line.sung ? CortetsuDesign.colorWashi : CortetsuDesign.colorOnSurfaceVariant
                opacity: !Lyrics.synced ? 0.85 : line.sung ? 1 : Math.max(0.14, 0.62 - line.distance * 0.14)
                Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                anchors.fill: parent
                enabled: Lyrics.synced && !!Players.active?.canSeek
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: Players.active.position = line.modelData.t / 1000
            }
        }
    }

    CortetsuText {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.empty && root.large
        text: Lyrics.source === "spotify" ? qsTr("Letra de Spotify") : Lyrics.source === "local" ? qsTr("Archivo local") : qsTr("Letra de LRCLIB")
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.labelSmallPx
        opacity: 0.6
    }
}
