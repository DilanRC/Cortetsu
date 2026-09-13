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
    property var activeNotifications: []
    readonly property var history: CortetsuNotifications.history

    function refreshActiveNotifications(): void {
        activeNotifications = Notifs.notClosed();
    }

    Component.onCompleted: refreshActiveNotifications()

    Connections {
        target: Notifs
        function onRevisionChanged(): void { root.refreshActiveNotifications(); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                title: qsTr("Notificaciones")
                detail: root.activeNotifications.length > 0
                    ? qsTr("%1 activas").arg(root.activeNotifications.length)
                    : qsTr("En silencio")
            }

            Item { Layout.fillWidth: true }

            CortetsuButton {
                visible: root.activeNotifications.length > 0 || root.history.length > 0
                compact: true
                label: qsTr("Limpiar")
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
                            ? qsTr("No molestar")
                            : qsTr("Notificaciones activadas")
                        textSize: CortetsuDesign.bodySmallPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnSurface
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: CortetsuNotifications.dnd
                            ? qsTr("Las alertas quedan en el historial sin interrumpirte")
                            : qsTr("Las nuevas alertas pueden aparecer como avisos")
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
            title: qsTr("Ahora")
            detail: root.activeNotifications.length === 0 ? qsTr("Nada nuevo") : ""
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
                // Use a numeric model for QObject-backed notifications. A raw
                // JS array makes ListView's model binding depend on delegate
                // creation and produces a binding cycle during live updates.
                model: root.activeNotifications.length
                delegate: NotificationComponents.Notification {
                    required property int index
                    focus: index === 0
                    width: activeList.width
                    modelData: root.activeNotifications[index]
                    props: ({})
                    expanded: false
                    screenState: root.screenState
                }

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: activeList.count === 0
                    kind: "empty"
                    title: qsTr("Todo limpio")
                    detail: qsTr("Las nuevas notificaciones aparecerán aquí")
                }
            }
        }

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Historial")
            detail: root.history.length > 0
                ? qsTr("%1 guardadas").arg(root.history.length)
                : qsTr("Vacío")
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
                    title: modelData.summary ?? qsTr("Notificación")
                    subtitle: [modelData.appName, modelData.timeStr]
                        .filter(value => value && value.length > 0)
                        .join(" · ") || modelData.body || qsTr("Notificación guardada")
                    onClicked: {}
                }

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: historyList.count === 0
                    kind: "empty"
                    title: qsTr("No hay notificaciones guardadas")
                    detail: qsTr("Las notificaciones descartadas se conservarán aquí")
                }
            }
        }
    }
}
