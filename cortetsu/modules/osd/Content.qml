import QtQuick
import Quickshell
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../../components"
import "../../services"

CortetsuPopupSurface {
    id: root

    required property var monitor
    required property var screenState
    required property real volume
    required property bool muted
    required property real brightness
    property bool hovered: false

    implicitWidth: 248
    implicitHeight: indicators.implicitHeight + CortetsuDesign.spacingStandard * 2 + 24

    Image {
        id: signatureMark
        x: CortetsuDesign.spacingStandard
        y: CortetsuDesign.spacingUnit
        width: 24
        height: 24
        source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")
        sourceSize.width: 48
        sourceSize.height: 48
        fillMode: Image.PreserveAspectFit
    }
    CortetsuText {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: CortetsuDesign.spacingCompact
        anchors.rightMargin: CortetsuDesign.spacingStandard
        text: qsTr("SYSTEM FEEDBACK")
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    Column {
        id: indicators
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: CortetsuDesign.spacingSection
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        Repeater {
            model: [
                {
                    icon: root.muted ? "volume_off" : "volume_up",
                    label: qsTr("Volume"),
                    value: root.volume,
                    muted: root.muted
                },
                {
                    icon: "brightness_6",
                    label: qsTr("Brightness"),
                    value: root.brightness,
                    muted: false
                }
            ]

            delegate: Item {
                id: indicator
                required property var modelData
                implicitWidth: indicators.width
                implicitHeight: 58

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusMedium
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.88)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.18)
                    outlined: true
                    hovered: indicatorMouse.containsMouse
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingStandard

                    Item {
                        width: 32
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter

                        CortetsuSurface {
                            anchors.fill: parent
                            radiusValue: CortetsuDesign.radiusSmall
                            baseColor: indicator.modelData.muted
                                ? Qt.alpha(CortetsuDesign.colorOnSurfaceVariant, 0.10)
                                : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                        }

                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: indicator.modelData.icon
                            color: indicator.modelData.muted
                                ? CortetsuDesign.colorOnSurfaceVariant
                                : CortetsuDesign.colorPrimary
                            iconSize: CortetsuTypography.iconMediumPx
                        }
                    }

                    Column {
                        width: Math.max(0, parent.width - x)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Item {
                            id: indicatorSummary
                            width: parent.width
                            height: Math.max(indicatorLabel.implicitHeight, indicatorValue.implicitHeight)

                            CortetsuText {
                                id: indicatorLabel
                                text: indicator.modelData.label
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }

                            CortetsuText {
                                id: indicatorValue
                                anchors.right: parent.right
                                text: indicator.modelData.muted
                                    ? qsTr("Muted")
                                    : indicator.modelData.value < 0
                                        ? qsTr("Unavailable")
                                    : qsTr("%1%").arg(Math.round(indicator.modelData.value * 100))
                                textSize: CortetsuTypography.labelSmallPx
                                font.weight: Font.DemiBold
                                color: indicator.modelData.muted || indicator.modelData.value < 0
                                    ? CortetsuDesign.colorOnSurfaceVariant
                                    : CortetsuDesign.colorOnSurface
                            }
                        }

                        CortetsuProgressBar {
                            width: parent.width
                            value: indicator.modelData.value
                            visibleWhenUnavailable: true
                            barHeight: 4
                            barRadius: 2
                            trackColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)
                            fillColor: indicator.modelData.muted || indicator.modelData.value < 0
                                ? CortetsuDesign.colorOnSurfaceVariant
                                : CortetsuDesign.colorPrimary
                            motionDuration: CortetsuDesign.motionFastMs
                        }
                    }
                }

                MouseArea {
                    id: indicatorMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.hovered = true
                    onExited: root.hovered = false
                    onWheel: event => {
                        if (index === 0) {
                            if (event.angleDelta.y > 0)
                                CortetsuAudio.incrementVolume();
                            else
                                CortetsuAudio.decrementVolume();
                        } else if (root.monitor?.supported) {
                            root.monitor.setBrightness(
                                root.brightness + (event.angleDelta.y > 0 ? 0.05 : -0.05)
                            );
                        }
                    }
                }
            }
        }
    }
}
