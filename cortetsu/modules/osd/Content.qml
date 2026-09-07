import QtQuick
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
    implicitHeight: indicators.implicitHeight + CortetsuDesign.spacingStandard * 2

    Column {
        id: indicators
        anchors.fill: parent
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
                                    : qsTr("%1%").arg(Math.round(indicator.modelData.value * 100))
                                textSize: CortetsuTypography.labelSmallPx
                                font.weight: Font.DemiBold
                                color: indicator.modelData.muted
                                    ? CortetsuDesign.colorOnSurfaceVariant
                                    : CortetsuDesign.colorOnSurface
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, indicator.modelData.value))
                                height: parent.height
                                radius: parent.radius
                                color: indicator.modelData.muted
                                    ? CortetsuDesign.colorOnSurfaceVariant
                                    : CortetsuDesign.colorPrimary

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
                        } else if (root.monitor) {
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
