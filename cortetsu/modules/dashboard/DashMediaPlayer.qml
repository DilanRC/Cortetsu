pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: player
    property bool compact: true
    property bool dashboardOpen: true
    readonly property MprisPlayer active: Players.active
    readonly property string art: Players.getArtUrl(active)

    CortetsuStateMessage {
        anchors.centerIn: parent
        width: parent.width
        visible: !player.active
        icon: "music_off"
        title: qsTr("Nada en reproducción")
        detail: qsTr("Los controles aparecen al reproducir en una app con MPRIS")
    }

    Timer {
        running: !!player.active && player.active.isPlaying && player.dashboardOpen
        interval: 1000
        repeat: true
        onTriggered: player.active.positionChanged()
    }

    GridLayout {
        anchors.fill: parent
        visible: !!player.active
        columns: player.compact ? 1 : 2
        columnSpacing: CortetsuDesign.spacingSection
        rowSpacing: CortetsuDesign.spacingStandard

        Rectangle {
            Layout.preferredWidth: player.compact ? parent.width : 300
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignTop
            Layout.rowSpan: player.compact ? 1 : 2
            radius: CortetsuDesign.radiusLarge
            color: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.6)
            clip: true
            CortetsuIcon { anchors.centerIn: parent; text: "music_note"; iconSize: CortetsuTypography.iconHeroPx; color: CortetsuDesign.colorOnPrimaryContainer; visible: cover.status !== Image.Ready }
            Image {
                id: cover
                anchors.fill: parent
                source: player.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 600
                sourceSize.height: 600
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingCompact

            DashLabel { visible: !player.compact; text: Players.getIdentity(player.active).toUpperCase() }
            CortetsuText {
                Layout.fillWidth: true
                text: player.active?.trackTitle || qsTr("Pista sin título")
                textSize: player.compact ? CortetsuTypography.titleSmallPx : CortetsuTypography.displayLargePx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
            CortetsuText {
                Layout.fillWidth: true
                text: player.active?.trackArtist ?? ""
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: player.compact ? CortetsuTypography.bodyPx : CortetsuTypography.titleSmallPx
                elide: Text.ElideRight
            }
            CortetsuText {
                Layout.fillWidth: true
                visible: !player.compact && (player.active?.trackAlbum ?? "") !== ""
                text: player.active?.trackAlbum ?? ""
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }

            Item { Layout.fillHeight: true }

            CortetsuProgressBar {
                Layout.fillWidth: true
                visible: (player.active?.length ?? 0) > 0
                value: player.active && player.active.length > 0 ? player.active.position / player.active.length : 0
                barHeight: 6
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !player.compact && (player.active?.length ?? 0) > 0
                CortetsuText { text: player.clock(player.active?.position ?? 0); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
                Item { Layout.fillWidth: true }
                CortetsuText { text: player.clock(player.active?.length ?? 0); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: CortetsuDesign.spacingStandard
                CortetsuButton { compact: true; icon: "skip_previous"; label: ""; tooltipText: qsTr("Pista anterior"); disabled: !player.active?.canGoPrevious; onClicked: player.active?.previous() }
                CortetsuButton { compact: true; active: true; icon: player.active?.isPlaying ? "pause" : "play_arrow"; label: ""; tooltipText: player.active?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir"); onClicked: player.active?.togglePlaying() }
                CortetsuButton { compact: true; icon: "skip_next"; label: ""; tooltipText: qsTr("Pista siguiente"); disabled: !player.active?.canGoNext; onClicked: player.active?.next() }
            }

            // Other players: one chip each, the active one filled.
            Flow {
                Layout.fillWidth: true
                visible: !player.compact && Players.list.length > 1
                spacing: CortetsuDesign.spacingCompact
                Repeater {
                    model: Players.list
                    Rectangle {
                        id: chip
                        required property MprisPlayer modelData
                        readonly property bool selected: chip.modelData === player.active
                        width: chipLabel.implicitWidth + 28
                        height: 40
                        radius: height / 2
                        color: selected ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.8)
                        CortetsuText { id: chipLabel; anchors.centerIn: parent; text: Players.getIdentity(chip.modelData); color: chip.selected ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Players.manualActive = chip.modelData }
                    }
                }
            }
        }
    }

    function clock(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }
}
