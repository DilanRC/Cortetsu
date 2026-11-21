pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// What is playing, beside the clock on the lock screen. Its controls take
// the pointer but never the keyboard: the keys stay on the password.
Item {
    id: root

    readonly property var player: Players.active
    signal handBackFocus()

    visible: !!player
    implicitWidth: 300
    implicitHeight: column.implicitHeight + CortetsuDesign.spacingStandard * 2

    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusLarge
        color: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.62)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.10)
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            Item {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                Rectangle {
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusMedium
                    color: Qt.alpha(CortetsuDesign.colorIndicator, 0.18)
                    visible: cover.status !== Image.Ready
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: CortetsuTypography.iconMediumPx
                        color: CortetsuDesign.colorPrimary
                    }
                }
                CortetsuRoundedImage {
                    id: cover
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusMedium
                    source: Players.getArtUrl(root.player)
                    visible: status === Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle || qsTr("Sin título")
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist || Players.getIdentity(root.player)
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: CortetsuDesign.spacingSpacious

            Repeater {
                model: [
                    { icon: "skip_previous", name: qsTr("Anterior"), enabled: root.player?.canGoPrevious ?? false, act: () => root.player?.previous() },
                    { icon: root.player?.isPlaying ? "pause" : "play_arrow", name: root.player?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir"), enabled: root.player?.canTogglePlaying ?? false, act: () => root.player?.togglePlaying(), main: true },
                    { icon: "skip_next", name: qsTr("Siguiente"), enabled: root.player?.canGoNext ?? false, act: () => root.player?.next() }
                ]
                delegate: Item {
                    id: control
                    required property var modelData
                    implicitWidth: modelData.main ? 44 : 36
                    implicitHeight: implicitWidth
                    opacity: modelData.enabled ? 1 : 0.4
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: control.modelData.main ? Qt.alpha(CortetsuDesign.colorIndicator, press.containsMouse ? 0.42 : 0.30)
                            : Qt.alpha(CortetsuDesign.colorWashi, press.containsMouse ? 0.10 : 0)
                    }
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: control.modelData.icon
                        iconSize: CortetsuTypography.iconMediumPx
                        color: CortetsuDesign.colorOnSurface
                    }
                    MouseArea {
                        id: press
                        anchors.fill: parent
                        enabled: control.modelData.enabled
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            control.modelData.act();
                            root.handBackFocus();
                        }
                    }
                }
            }
        }
    }
}
