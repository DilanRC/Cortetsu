pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// What is playing. Compact, it is a margin note: a small cover, the title in
// ink and the line being sung. Full, the cover and controls stand on the
// left and the lyrics fill the rest.
Item {
    id: player
    property bool compact: true
    property bool dashboardOpen: true
    readonly property MprisPlayer active: Players.active
    readonly property string art: Players.getArtUrl(active)

    Timer {
        running: !!player.active && player.active.isPlaying && player.dashboardOpen
        interval: 1000
        repeat: true
        onTriggered: player.active.positionChanged()
    }

    function clock(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    // ------------------------------------------------------------ nothing on

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width
        visible: !player.active
        spacing: CortetsuDesign.spacingCompact
        Text {
            Layout.alignment: player.compact ? Qt.AlignLeft : Qt.AlignHCenter
            visible: !player.compact
            text: "静"
            font.family: CortetsuDesign.fontKanji
            font.pixelSize: CortetsuTypography.inkHeroPx
            color: CortetsuDesign.colorWashi
            opacity: 0.08
        }
        DashInk {
            Layout.alignment: player.compact ? Qt.AlignLeft : Qt.AlignHCenter
            text: qsTr("Nada en reproducción")
            textSize: player.compact ? CortetsuTypography.inkLinePx : CortetsuTypography.inkTitlePx
            font.italic: true
        }
        CortetsuText {
            Layout.alignment: player.compact ? Qt.AlignLeft : Qt.AlignHCenter
            Layout.fillWidth: player.compact
            text: qsTr("Los controles aparecen al reproducir en una app con MPRIS")
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.bodySmallPx
            wrapMode: Text.Wrap
        }
    }

    // --------------------------------------------------------------- compact

    ColumnLayout {
        anchors.fill: parent
        visible: !!player.active && player.compact
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard
            DashCover { size: 56; art: player.art }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                DashInk {
                    Layout.fillWidth: true
                    text: player.active?.trackTitle || qsTr("Pista sin título")
                    textSize: CortetsuTypography.inkLinePx
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: player.active?.trackArtist ?? ""
                    color: CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.bodySmallPx
                    elide: Text.ElideRight
                }
            }
            CortetsuButton { compact: true; active: true; icon: player.active?.isPlaying ? "pause" : "play_arrow"; label: ""; tooltipText: player.active?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir"); onClicked: player.active?.togglePlaying() }
        }
    }

    // ------------------------------------------------------------------ full

    RowLayout {
        anchors.fill: parent
        visible: !!player.active && !player.compact
        spacing: CortetsuDesign.spacingSection * 1.5

        ColumnLayout {
            Layout.preferredWidth: 300
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingCompact

            DashCover { size: 232; art: player.art }
            Item { Layout.preferredHeight: CortetsuDesign.spacingCompact }
            DashInk {
                Layout.fillWidth: true
                text: player.active?.trackTitle || qsTr("Pista sin título")
                textSize: CortetsuTypography.inkTitlePx
                font.weight: Font.Normal
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
            CortetsuText {
                Layout.fillWidth: true
                text: [player.active?.trackArtist, player.active?.trackAlbum].filter(s => !!s).join(" · ")
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }

            // Progress as a brush stroke over a faint one.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                visible: (player.active?.length ?? 0) > 0
                CortetsuBrushStroke { anchors.fill: parent; ink: CortetsuDesign.colorWashi; inkAlpha: 0.08 }
                CortetsuBrushStroke {
                    height: parent.height
                    width: Math.max(height * 3, parent.width * (player.active && player.active.length > 0 ? player.active.position / player.active.length : 0))
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: (player.active?.length ?? 0) > 0
                CortetsuText { text: player.clock(player.active?.position ?? 0); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
                Item { Layout.fillWidth: true }
                CortetsuText { text: player.clock(player.active?.length ?? 0); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
            }
            RowLayout {
                Layout.fillWidth: true
                DashTransport { active: player.active }
                Item { Layout.fillWidth: true }
                // Other players, by name; the one in control is in ink.
                Repeater {
                    model: Players.list.length > 1 ? Players.list : []
                    CortetsuText {
                        id: chip
                        required property MprisPlayer modelData
                        readonly property bool selected: chip.modelData === player.active
                        text: Players.getIdentity(chip.modelData)
                        color: selected ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
                        font.weight: selected ? Font.DemiBold : Font.Normal
                        textSize: CortetsuTypography.bodySmallPx
                        MouseArea { anchors.fill: parent; anchors.margins: -12; cursorShape: Qt.PointingHandCursor; onClicked: Players.manualActive = chip.modelData }
                    }
                }
            }
        }

        DashLyrics {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
