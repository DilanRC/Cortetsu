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
    implicitHeight: column.implicitHeight + 36

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
            Layout.fillWidth: true
            Layout.preferredHeight: width
            Rectangle {
                anchors.fill: parent
                radius: 22
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
                radius: 22
                source: Players.getArtUrl(root.player)
            }
        }
        CortetsuText {
            Layout.fillWidth: true
            text: root.player?.trackTitle || qsTr("Sin título")
            textSize: CortetsuTypography.titleSmallPx
            font.weight: Font.DemiBold
            color: CortetsuDesign.colorOnPrimaryContainer
            elide: Text.ElideRight
        }
        CortetsuText {
            Layout.fillWidth: true
            Layout.topMargin: -6
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
}
