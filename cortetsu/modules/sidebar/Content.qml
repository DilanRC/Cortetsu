pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../notifications" as NotificationComponents
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property var screenState
    readonly property var active: Notifs.notClosed()
    readonly property var history: CortetsuNotifications.history

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                title: qsTr("Notifications")
                detail: root.active.length > 0
                    ? qsTr("%1 active").arg(root.active.length)
                    : qsTr("Quiet")
            }

            Item { Layout.fillWidth: true }

            CortetsuButton {
                visible: root.active.length > 0 || root.history.length > 0
                compact: true
                label: qsTr("Clear")
                icon: "delete_sweep"
                onClicked: {
                    CortetsuNotifications.clear();
                    Notifs.clear();
                }
            }
        }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 66
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: CortetsuNotifications.dnd
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.10)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.74)
            outlineColor: CortetsuNotifications.dnd
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.38)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.20)
            outlined: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                Item {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusSmall
                        baseColor: CortetsuNotifications.dnd
                            ? Qt.alpha(CortetsuDesign.colorWarning, 0.14)
                            : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                    }

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"
                        iconSize: CortetsuDesign.iconMediumPx
                        color: CortetsuNotifications.dnd
                            ? CortetsuDesign.colorWarning
                            : CortetsuDesign.colorPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    CortetsuText {
                        Layout.fillWidth: true
                        text: CortetsuNotifications.dnd
                            ? qsTr("Do not disturb")
                            : qsTr("Notifications enabled")
                        textSize: CortetsuDesign.bodySmallPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnSurface
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: CortetsuNotifications.dnd
                            ? qsTr("Alerts remain in history without interrupting you")
                            : qsTr("New alerts may appear as popups")
                        textSize: CortetsuDesign.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                CortetsuToggle {
                    checked: CortetsuNotifications.dnd
                    onToggled: checked => CortetsuNotifications.dnd = checked
                }
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Now")
            detail: root.active.length === 0 ? qsTr("Nothing new") : ""
        }

        CortetsuSurface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            baseColor: "transparent"
            outlined: false

            ListView {
                id: activeList
                anchors.fill: parent
                clip: true
                spacing: CortetsuDesign.spacingCompact
                model: root.active
                delegate: NotificationComponents.Notification {
                    required property int index
                    width: activeList.width
                    modelData: root.active[index]
                    props: ({})
                    expanded: false
                    screenState: root.screenState
                }

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: activeList.count === 0
                    kind: "empty"
                    title: qsTr("All clear")
                    detail: qsTr("New notifications will appear here")
                }
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("History")
            detail: root.history.length > 0
                ? qsTr("%1 saved").arg(root.history.length)
                : qsTr("Empty")
        }

        CortetsuSurface {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(historyList.contentHeight, 3 * CortetsuDesign.rowHeight)
            baseColor: "transparent"
            outlined: false

            ListView {
                id: historyList
                anchors.fill: parent
                clip: true
                spacing: CortetsuDesign.spacingUnit
                model: root.history
                delegate: CortetsuListRow {
                    required property var modelData
                    width: historyList.width
                    icon: modelData.urgency >= 2 ? "priority_high" : "history"
                    title: modelData.summary ?? qsTr("Notification")
                    subtitle: [modelData.appName, modelData.timeStr]
                        .filter(value => value && value.length > 0)
                        .join(" · ") || modelData.body || qsTr("Saved notification")
                    onClicked: {}
                }

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: historyList.count === 0
                    kind: "empty"
                    title: qsTr("No saved notifications")
                    detail: qsTr("Dismissed notifications will be kept here")
                }
            }
        }
    }
}
