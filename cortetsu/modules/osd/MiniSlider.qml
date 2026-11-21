pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The transient OSD: what just changed, read back from the system. It is
// not a control: it takes no pointer and no focus, and goes away on its own.
// A level (volume, brightness) shows its bar; a state (the microphone) shows
// its name and nothing to drag. Silence and a muted microphone read
// differently from a plain percentage. A power profile is a state too: its
// name, as power-profiles-daemon reports it after the change. Media is a
// state as well: the track and whether it now plays or is paused.
Item {
    id: root

    // "volume" | "brightness" | "microphone" | "profile" | "media"
    required property string kind
    required property real value
    required property real maximum
    required property bool available
    required property bool muted
    // The device the reading belongs to, when the system names it.
    property string name: ""
    // Media: the artist under the title, and the cover in place of the icon.
    property string detail: ""
    property string art: ""
    readonly property bool level: kind !== "microphone" && kind !== "profile" && kind !== "media"
    // For media, `value` is 1 while playing and 0 while paused.
    readonly property bool playing: kind === "media" && value > 0.5
    // PowerProfile: 0 power saver, 1 balanced, 2 performance.
    readonly property int profile: kind === "profile" ? Math.round(value) : -1
    // A muted microphone is the one reading here that asks for attention.
    readonly property bool attention: kind === "microphone" && muted && available
    readonly property color tone: attention ? CortetsuDesign.colorVermillion
        : muted || !available ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorIndicator

    readonly property real progress: available && maximum > 0
        ? Math.max(0, Math.min(1, value / maximum)) : 0
    property real presentedProgress: progress
    Behavior on presentedProgress {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }
    readonly property string icon: kind === "volume"
        ? muted || value <= 0 ? "volume_off" : "volume_up"
        : kind === "microphone" ? (muted || !available ? "mic_off" : "mic")
        : kind === "profile" ? (profile === 0 ? "energy_savings_leaf" : profile === 2 ? "rocket_launch" : "balance")
        : kind === "media" ? (playing ? "play_arrow" : "pause")
        : "light_mode"
    readonly property string label: name.length > 0 ? name
        : kind === "volume" ? qsTr("Volumen") : kind === "microphone" ? qsTr("Micrófono")
        : kind === "profile" ? qsTr("Perfil de energía") : kind === "media" ? qsTr("Multimedia") : qsTr("Brillo")
    readonly property string amount: !available ? qsTr("No disponible")
        : kind === "microphone" ? (muted ? qsTr("Silenciado") : qsTr("Activo"))
        : kind === "profile" ? (profile === 0 ? qsTr("Ahorro") : profile === 2 ? qsTr("Rendimiento") : qsTr("Equilibrado"))
        : kind === "media" ? (playing ? qsTr("Reproduciendo") : qsTr("En pausa"))
        : muted ? qsTr("Silenciado") : `${Math.round(value * 100)}%`

    Accessible.role: Accessible.AlertMessage
    Accessible.name: `${root.label}: ${root.amount}`

    implicitWidth: kind === "media" ? 360 : 320
    implicitHeight: level ? 64 : 60

    // A capsule: ends fully round in every theme.
    CortetsuPopupSurface {
        anchors.fill: parent
        popupRadius: height / 2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 22
            spacing: CortetsuDesign.spacingStandard

            // The icon in a disc of its own tone: the kind reads before the
            // words do.
            Rectangle {
                visible: !cover.visible
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: width / 2
                color: Qt.alpha(root.tone, root.attention ? 0.20 : 0.16)
                border.width: 1
                border.color: Qt.alpha(root.tone, 0.34)

                CortetsuIcon {
                    anchors.centerIn: parent
                    iconSize: 20
                    text: root.icon
                    color: root.attention ? CortetsuDesign.colorVermillion
                        : root.muted || !root.available ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorOnSurface
                }
            }

            // The cover of the track, when the player gives one; a missing
            // or broken image falls back to the icon disc.
            CortetsuRoundedImage {
                id: cover
                objectName: "osdCover"
                visible: root.kind === "media" && root.art.length > 0 && status === Image.Ready
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                source: root.kind === "media" ? root.art : ""
                radius: width / 2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.level ? 6 : 1

                RowLayout {
                    Layout.fillWidth: true
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.label
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        objectName: "osdAmount"
                        text: root.amount
                        textSize: CortetsuTypography.bodySmallPx
                        font.weight: root.level ? Font.Normal : Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: root.attention ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                    }
                }

                CortetsuText {
                    objectName: "osdDetail"
                    Layout.fillWidth: true
                    visible: root.kind === "media" && root.detail.length > 0
                    text: root.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }

                Item {
                    visible: root.level
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12

                    Rectangle {
                        id: track
                        objectName: "osdTrack"
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: height / 2
                        color: CortetsuDesign.colorSurfaceHigh

                        Rectangle {
                            width: track.width * root.presentedProgress
                            height: parent.height
                            radius: height / 2
                            color: root.tone
                        }
                    }
                    // Where the level stands; a reading, not a handle.
                    Rectangle {
                        visible: root.available && !root.muted
                        width: 12
                        height: 12
                        radius: width / 2
                        x: Math.max(0, Math.min(parent.width - width, track.width * root.presentedProgress - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        color: CortetsuDesign.colorWashi
                        border.width: 2
                        border.color: root.tone
                    }
                }
            }
        }
    }
}
