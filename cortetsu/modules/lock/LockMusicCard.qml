pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// What plays, as a tall card at the clock's side (Nebula's music wing): the
// cover large, title, artist and the controls the player supports. A
// control hands the keyboard back to the password at once.
Item {
    id: root

    readonly property var player: Players.active
    signal handBackFocus()

    implicitWidth: 300
    implicitHeight: column.implicitHeight + 36 + 86

    Rectangle {
        anchors.fill: parent
        radius: 32
        color: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.82)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorPrimary, 0.35)
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 10

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 132
            Layout.preferredHeight: 132
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(CortetsuDesign.colorSumi, 0.4)
                CortetsuIcon {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready
                    text: "music_note"
                    iconSize: 56
                    color: CortetsuDesign.colorOnPrimaryContainer
                }
            }
            CortetsuRoundedImage {
                id: cover
                anchors.fill: parent
                radius: width / 2
                source: Players.getArtUrl(root.player)
            }
        }
        CortetsuText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.player?.trackTitle || qsTr("Sin título")
            textSize: CortetsuTypography.titleSmallPx
            font.weight: Font.DemiBold
            color: CortetsuDesign.colorOnPrimaryContainer
            elide: Text.ElideRight
        }
        CortetsuText {
            Layout.fillWidth: true
            Layout.topMargin: -6
            horizontalAlignment: Text.AlignHCenter
            text: root.player?.trackArtist || Players.getIdentity(root.player)
            textSize: CortetsuTypography.bodySmallPx
            color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.75)
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: CortetsuDesign.spacingStandard
            Repeater {
                model: [
                    { icon: "skip_previous", tip: qsTr("Anterior"), can: root.player?.canGoPrevious, act: () => root.player?.previous() },
                    { icon: root.player?.isPlaying ? "pause" : "play_arrow", tip: qsTr("Reproducir o pausar"), can: root.player?.canTogglePlaying, act: () => root.player?.togglePlaying(), main: true },
                    { icon: "skip_next", tip: qsTr("Siguiente"), can: root.player?.canGoNext, act: () => root.player?.next() }
                ]
                delegate: CortetsuButton {
                    required property var modelData
                    pill: true
                    active: !!modelData.main
                    activeFocusOnTab: false
                    icon: modelData.icon
                    label: ""
                    tooltipText: modelData.tip
                    disabled: !modelData.can
                    onClicked: {
                        modelData.act();
                        root.handBackFocus();
                    }
                }
            }
        }
    }

    // Bars at the foot: the spectrum when cava runs, otherwise how far into
    // the track it is. Never invented motion.
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22
        height: 64
        spacing: 3
        readonly property int count: 20
        readonly property real played: (root.player?.length ?? 0) > 0 ? root.player.position / root.player.length : 0
        Repeater {
            model: parent.count
            delegate: Rectangle {
                required property int index
                readonly property real level: CortetsuSpectrum.available
                    ? (CortetsuSpectrum.values[Math.floor(index * CortetsuSpectrum.values.length / 20)] ?? 0) / 100
                    : (index + 1) / 20 <= parent.played ? 1 : 0.25
                width: (parent.width - parent.spacing * 19) / 20
                height: Math.max(4, 64 * (CortetsuSpectrum.available ? level : 0.35 + 0.25 * Math.sin(index * 0.9)) * (CortetsuSpectrum.available ? 1 : level))
                anchors.bottom: parent.bottom
                radius: width / 2
                color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.85)
            }
        }
    }
}
