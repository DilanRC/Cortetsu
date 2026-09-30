import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: Hypr.activeToplevel ? child.implicitWidth : -CortetsuTokens.padding.extraLargeIncreased
    implicitHeight: child.implicitHeight

    Column {
        id: child

        anchors.centerIn: parent
        spacing: CortetsuTokens.spacing.medium

        RowLayout {
            id: detailsRow

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: CortetsuTokens.spacing.medium

            IconImage {
                id: icon

                asynchronous: false
                Layout.alignment: Qt.AlignVCenter
                implicitSize: details.implicitHeight
                source: Icons.getAppIcon(Hypr.activeToplevel?.lastIpcObject.class ?? "", "image-missing")
            }

            ColumnLayout {
                id: details

                spacing: 0
                Layout.fillWidth: true

                CortetsuText {
                    Layout.fillWidth: true
                    text: Hypr.activeToplevel?.title ?? ""
                    font: CortetsuTokens.font.body.medium
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: Hypr.activeToplevel?.lastIpcObject.class ?? ""
                    color: CortetsuColours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            Item {
                implicitWidth: expandIcon.implicitHeight + CortetsuTokens.padding.small
                implicitHeight: expandIcon.implicitHeight + CortetsuTokens.padding.small

                Layout.alignment: Qt.AlignVCenter

                CortetsuStateLayer {
                    radius: CortetsuTokens.rounding.large
                    onClicked: root.popouts.detachRequested("winfo")
                }

                CortetsuIcon {
                    id: expandIcon

                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: font.pointSize * 0.05

                    text: "chevron_right"

                    fontStyle: CortetsuTokens.font.icon.large
                }
            }
        }

        ClippingWrapperRectangle {
            color: "transparent"
            radius: CortetsuTokens.rounding.medium

            ScreencopyView {
                id: preview

                captureSource: visible ? (Hypr.activeToplevel?.wayland ?? null) : null // qmllint disable unresolved-type
                live: visible

                constraintSize.width: CortetsuTokens.sizes.bar.windowPreviewSize
                constraintSize.height: CortetsuTokens.sizes.bar.windowPreviewSize
            }
        }
    }
}
