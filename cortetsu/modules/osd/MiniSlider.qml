pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property string kind
    required property real value
    required property real maximum
    required property bool available
    required property bool muted

    readonly property real progress: available && maximum > 0
        ? Math.max(0, Math.min(1, value / maximum)) : 0
    readonly property string icon: kind === "volume"
        ? muted || value <= 0 ? "volume_off" : "volume_up"
        : "light_mode"
    readonly property string label: kind === "volume" ? qsTr("Volumen") : qsTr("Brillo")
    readonly property string amount: available
        ? `${Math.round(value * 100)}%` : qsTr("No disponible")

    implicitWidth: 236
    implicitHeight: 64

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
                color: CortetsuDesign.colorPrimary
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
                        text: root.amount
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurface
                    }
                }

                Rectangle {
                    id: track
                    Layout.fillWidth: true
                    Layout.preferredHeight: 5
                    radius: height / 2
                    color: CortetsuDesign.colorSurfaceHigh

                    Rectangle {
                        width: track.width * root.progress
                        height: parent.height
                        radius: height / 2
                        color: CortetsuDesign.colorPrimary
                        Behavior on width {
                            NumberAnimation {
                                duration: CortetsuDesign.motionFastMs
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }
}
