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
    implicitHeight: column.implicitHeight + 36 + 92

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
                // The note only when there is no cover at all; while the next
                // track's cover loads, the disc stays as it is.
                CortetsuIcon {
                    anchors.centerIn: parent
                    visible: cover.status === Image.Error || String(cover.source).length === 0
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

    // Keeps the position fresh while the lock shows; MPRIS only reports it
    // when asked.
    Timer {
        running: root.visible && !!root.player?.isPlaying
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }
    Component.onCompleted: Lyrics.consumers += 1
    Component.onDestruction: Lyrics.consumers -= 1

    function clock(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    // The foot: the line being sung, then a real seek bar (drag or click to
    // move through the track, when the player allows it) with its times.
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 8

        CortetsuText {
            objectName: "lockLyricLine"
            width: parent.width
            visible: text.length > 0
            text: Lyrics.currentLine
            horizontalAlignment: Text.AlignHCenter
            textSize: CortetsuTypography.bodySmallPx
            font.italic: true
            color: CortetsuDesign.colorOnPrimaryContainer
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        RowLayout {
            width: parent.width
            spacing: 8
            readonly property real length: root.player?.length ?? 0
            readonly property real progress: length > 0 ? Math.min(1, (root.player?.position ?? 0) / length) : 0

            CortetsuText {
                text: root.clock(seek.pressed ? seek.preview * parent.length : (root.player?.position ?? 0))
                textSize: CortetsuTypography.labelSmallPx
                font.features: ({ "tnum": 1 })
                color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.8)
            }
            Item {
                id: seekBox
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                readonly property real shown: seek.pressed ? seek.preview : parent.progress
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.3)
                    Rectangle {
                        width: parent.width * seekBox.shown
                        height: parent.height
                        radius: 2
                        color: CortetsuDesign.colorOnPrimaryContainer
                    }
                }
                Rectangle {
                    objectName: "lockSeekKnob"
                    width: seek.pressed || seek.containsMouse ? 14 : 10
                    height: width
                    radius: width / 2
                    x: parent.width * seekBox.shown - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: CortetsuDesign.colorOnPrimaryContainer
                }
                MouseArea {
                    id: seek
                    objectName: "lockSeek"
                    anchors.fill: parent
                    enabled: !!root.player?.canSeek && (root.player?.length ?? 0) > 0
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    property real preview: 0
                    function at(x: real): real { return Math.max(0, Math.min(1, x / width)); }
                    onPressed: mouse => preview = at(mouse.x)
                    onPositionChanged: mouse => { if (pressed) preview = at(mouse.x); }
                    onReleased: mouse => {
                        root.player.position = at(mouse.x) * root.player.length;
                        root.handBackFocus();
                    }
                }
            }
            CortetsuText {
                text: root.clock(parent.length)
                textSize: CortetsuTypography.labelSmallPx
                font.features: ({ "tnum": 1 })
                color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.8)
            }
        }
    }
}
