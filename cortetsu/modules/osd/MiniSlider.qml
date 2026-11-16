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
// name, as power-profiles-daemon reports it after the change.
Item {
    id: root

    // "volume" | "brightness" | "microphone" | "profile"
    required property string kind
    required property real value
    required property real maximum
    required property bool available
    required property bool muted
    // The device the reading belongs to, when the system names it.
    property string name: ""
    readonly property bool level: kind !== "microphone" && kind !== "profile"
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
        : "light_mode"
    readonly property string label: name.length > 0 ? name
        : kind === "volume" ? qsTr("Volumen") : kind === "microphone" ? qsTr("Micrófono")
        : kind === "profile" ? qsTr("Perfil de energía") : qsTr("Brillo")
    readonly property string amount: !available ? qsTr("No disponible")
        : kind === "microphone" ? (muted ? qsTr("Silenciado") : qsTr("Activo"))
        : kind === "profile" ? (profile === 0 ? qsTr("Ahorro") : profile === 2 ? qsTr("Rendimiento") : qsTr("Equilibrado"))
        : muted ? qsTr("Silenciado") : `${Math.round(value * 100)}%`

    Accessible.role: Accessible.AlertMessage
    Accessible.name: `${root.label}: ${root.amount}`

    implicitWidth: 236
    implicitHeight: level ? 64 : 52

    CortetsuPopupSurface {
        anchors.fill: parent
        popupRadius: CortetsuDesign.radiusMedium

        RowLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                iconSize: 20
                text: root.icon
                color: root.tone
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingUnit

                RowLayout {
                    Layout.fillWidth: true
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.label
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        objectName: "osdAmount"
                        text: root.amount
                        textSize: CortetsuTypography.bodySmallPx
                        font.weight: root.level ? Font.Normal : Font.DemiBold
                        color: root.attention ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurface
                    }
                }

                Rectangle {
                    id: track
                    objectName: "osdTrack"
                    visible: root.level
                    Layout.fillWidth: true
                    Layout.preferredHeight: 5
                    radius: height / 2
                    color: CortetsuDesign.colorSurfaceHigh

                    Rectangle {
                        width: track.width * root.presentedProgress
                        height: parent.height
                        radius: height / 2
                        color: root.tone
                    }
                }
            }
        }
    }
}
