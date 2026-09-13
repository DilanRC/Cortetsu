pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Rectangle {
    id: root

    property string title: ""
    property string icon: "monitor_heart"
    property string headline: ""
    property string subtitle: ""
    property real progress: -1
    property var rows: []
    property string modeLabel: ""

    signal modeRequested()

    implicitHeight: 164
    radius: CortetsuDesign.radiusLarge
    color: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
    border.width: 0

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        Row {
            width: parent.width
            height: 24
            spacing: CortetsuDesign.spacingCompact

            CortetsuIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                color: CortetsuDesign.colorPrimary
                iconSize: CortetsuTypography.iconMediumPx
            }

            CortetsuText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(40, parent.width - x - (modeButton.visible ? modeButton.width + 12 : 0))
                text: root.title
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelMediumPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Rectangle {
                id: modeButton
                visible: root.modeLabel.length > 0
                width: 46
                height: 24
                radius: CortetsuDesign.radiusPill
                color: Qt.alpha(CortetsuDesign.colorPrimaryContainer, modeMouse.containsMouse ? 0.9 : 0.58)

                CortetsuText {
                    anchors.centerIn: parent
                    text: root.modeLabel
                    color: CortetsuDesign.colorOnPrimaryContainer
                    textSize: CortetsuTypography.labelSmallPx
                }

                MouseArea {
                    id: modeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.modeRequested()
                }
            }
        }

        Row {
            width: parent.width
            height: 32

            CortetsuText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.46
                text: root.headline
                color: CortetsuDesign.colorOnSurface
                textSize: CortetsuTypography.titleLargePx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.54
                text: root.subtitle
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }
        }

        CortetsuProgressBar {
            width: parent.width
            value: root.progress
        }

        Item {
            width: parent.width
            height: 48

            Row {
                anchors.fill: parent
                spacing: CortetsuDesign.spacingStandard

                Repeater {
                    model: root.rows

                    delegate: Column {
                        required property var modelData
                        width: Math.max(1, (parent.width - parent.spacing * Math.max(0, root.rows.length - 1)) / Math.max(1, root.rows.length))
                        spacing: 2

                        CortetsuText {
                            width: parent.width
                            text: String(modelData?.value ?? "—")
                            color: CortetsuDesign.colorOnSurface
                            textSize: CortetsuTypography.bodySmallPx
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            width: parent.width
                            text: String(modelData?.label ?? "")
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.labelSmallPx
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
