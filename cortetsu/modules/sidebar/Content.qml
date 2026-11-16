pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../notifications" as NotificationComponents
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The notification center. What is on screen now comes first, grouped by
// the app that sent it; the saved history fills the rest and can be
// searched once it is long enough to need it. Do not disturb is one open
// row, not a card that repeats the header.
Item {
    id: root

    required property var screenState
    property var activeNotifications: []
    readonly property var history: CortetsuNotifications.history
    property string query: ""
    readonly property var filteredHistory: {
        const needle = root.query.trim().toLocaleLowerCase();
        if (needle.length === 0)
            return root.history;
        return root.history.filter(entry => [entry.summary, entry.body, entry.appName]
            .some(value => typeof value === "string" && value.toLocaleLowerCase().includes(needle)));
    }
    // How many live notifications each app has, for its group heading.
    readonly property var groupCounts: {
        const counts = {};
        for (const item of root.activeNotifications) {
            const key = item?.appName ?? "";
            counts[key] = (counts[key] ?? 0) + 1;
        }
        return counts;
    }

    // Keeps arrival order between groups (a group sits where its first
    // notification arrived) and inside each group.
    function groupByApp(items: var): var {
        const order = [];
        const groups = {};
        for (const item of items) {
            const key = item?.appName ?? "";
            if (!(key in groups)) {
                groups[key] = [];
                order.push(key);
            }
            groups[key].push(item);
        }
        return order.reduce((all, key) => all.concat(groups[key]), []);
    }

    function refreshActiveNotifications(): void {
        activeNotifications = groupByApp(Notifs.notClosed());
    }

    Component.onCompleted: refreshActiveNotifications()

    Connections {
        target: Notifs
        // Deferred: a delegate destroyed by a model change unlocks its item,
        // which bumps `revision` again while the ListView is still applying
        // the model. callLater also folds a clear of N items into one update.
        function onRevisionChanged(): void { Qt.callLater(root.refreshActiveNotifications); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Notificaciones")
                detail: root.activeNotifications.length === 1 ? qsTr("1 en pantalla")
                    : root.activeNotifications.length > 1 ? qsTr("%1 en pantalla").arg(root.activeNotifications.length)
                    : qsTr("Nada en pantalla")
            }

            CortetsuButton {
                visible: root.activeNotifications.length > 0 || root.history.length > 0
                compact: true
                label: qsTr("Limpiar todo")
                icon: "delete_sweep"
                onClicked: {
                    CortetsuNotifications.clear();
                    Notifs.clear();
                }
            }
        }

        // Do not disturb: a state the user chose, so it is a row with its
        // switch, and the line under it says what it changes.
        RowLayout {
            objectName: "notificationsDnd"
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: CortetsuNotifications.dnd ? "notifications_off" : "notifications"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuNotifications.dnd ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("No molestar")
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: CortetsuNotifications.dnd
                        ? qsTr("Los avisos van al historial sin aparecer")
                        : qsTr("Los avisos nuevos aparecen en pantalla")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuToggle {
                accessibleName: qsTr("No molestar")
                checked: CortetsuNotifications.dnd
                onToggled: checked => CortetsuNotifications.setDnd(checked)
            }
        }

        CortetsuDivider { Layout.fillWidth: true }

        // --- Now -------------------------------------------------------------

        ListView {
            id: activeList
            objectName: "notificationsActive"
            Layout.fillWidth: true
            // As tall as what is on screen, up to a little over half the
            // panel; the history keeps the rest.
            Layout.preferredHeight: Math.min(contentHeight, root.height * 0.55)
            visible: count > 0
            clip: true
            spacing: CortetsuDesign.spacingCompact
            // Use a numeric model for QObject-backed notifications. A raw
            // JS array makes ListView's model binding depend on delegate
            // creation and produces a binding cycle during live updates.
            model: root.activeNotifications.length
            delegate: Column {
                id: entry
                required property int index
                readonly property var item: root.activeNotifications[index]
                readonly property string app: item?.appName ?? ""
                readonly property bool firstOfGroup: index === 0
                    || (root.activeNotifications[index - 1]?.appName ?? "") !== app
                width: activeList.width
                spacing: CortetsuDesign.spacingUnit

                // The app once per group, with its count when it sent more
                // than one: the cards under it do not repeat it.
                // An app can be muted from its group: its next notifications
                // go straight to the history (Ajustes → Notificaciones lists
                // the muted apps).
                RowLayout {
                    readonly property bool muted: CortetsuConfig.mutedNotificationApps.includes(entry.app)
                    visible: entry.firstOfGroup
                    width: parent.width
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuText {
                        Layout.fillWidth: true
                        Layout.topMargin: entry.index === 0 ? 0 : CortetsuDesign.spacingCompact
                        text: (entry.app.length > 0 ? entry.app : qsTr("Sistema"))
                            + ((root.groupCounts[entry.app] ?? 0) > 1 ? ` · ${root.groupCounts[entry.app]}` : "")
                            + (parent.muted ? qsTr(" · silenciada") : "")
                        textSize: CortetsuTypography.labelMediumPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }

                    CortetsuButton {
                        visible: entry.app.length > 0
                        compact: true
                        icon: parent.muted ? "notifications_active" : "notifications_off"
                        label: ""
                        tooltipText: parent.muted ? qsTr("Volver a mostrar los avisos de %1").arg(entry.app)
                            : qsTr("Silenciar %1: sus avisos irán al historial sin aparecer").arg(entry.app)
                        onClicked: CortetsuConfig.setNotificationAppMuted(entry.app, !parent.muted)
                    }
                }

                NotificationComponents.Notification {
                    focus: entry.index === 0
                    width: parent.width
                    modelData: entry.item
                    props: ({})
                    expanded: false
                    screenState: root.screenState
                }
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: activeList.count === 0
            text: qsTr("No hay avisos en pantalla.")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        // --- History -------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: CortetsuDesign.spacingCompact
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Historial")
                detail: root.history.length === 0 ? qsTr("Vacío")
                    : root.query.length > 0 ? qsTr("%1 de %2").arg(root.filteredHistory.length).arg(root.history.length)
                    : root.history.length === 1 ? qsTr("1 guardada") : qsTr("%1 guardadas").arg(root.history.length)
            }
        }

        // A filter only when there is enough to filter (ADR-008, rule 5).
        CortetsuSearchBar {
            objectName: "notificationsSearch"
            Layout.fillWidth: true
            visible: root.history.length > 8
            compact: true
            placeholderText: qsTr("Buscar en el historial")
            text: root.query
            onTextChanged: root.query = text
            Keys.onEscapePressed: event => {
                if (text.length > 0) {
                    clear();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }

        ListView {
            id: historyList
            objectName: "notificationsHistory"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: CortetsuDesign.rowHeight
            clip: true
            model: root.filteredHistory
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool urgent: (modelData.urgency ?? 0) >= 2
                width: historyList.width
                implicitHeight: Math.max(CortetsuDesign.rowHeight, texts.implicitHeight + CortetsuDesign.spacingCompact * 2)
                height: implicitHeight

                CortetsuDivider {
                    visible: row.index > 0
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: CortetsuDesign.spacingUnit
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuIcon {
                        text: row.urgent ? "priority_high" : "notifications"
                        iconSize: CortetsuTypography.iconSmallPx
                        color: row.urgent ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                    }

                    ColumnLayout {
                        id: texts
                        Layout.fillWidth: true
                        spacing: 0
                        CortetsuText {
                            Layout.fillWidth: true
                            text: row.modelData.summary || qsTr("Notificación")
                            textSize: CortetsuTypography.bodySmallPx
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        CortetsuText {
                            Layout.fillWidth: true
                            text: [row.modelData.appName, row.modelData.timeStr]
                                .filter(value => value && value.length > 0)
                                .join(" · ") || qsTr("Notificación guardada")
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    CortetsuButton {
                        compact: true
                        icon: "close"
                        label: ""
                        tooltipText: qsTr("Quitar del historial")
                        onClicked: CortetsuNotifications.dismiss(row.modelData.id)
                    }
                }
            }

            CortetsuStateMessage {
                anchors.centerIn: parent
                width: parent.width
                visible: historyList.count === 0
                kind: "empty"
                title: root.query.length > 0 ? qsTr("Nada coincide con «%1»").arg(root.query)
                    : qsTr("No hay notificaciones guardadas")
                detail: root.query.length > 0 ? qsTr("Prueba con el nombre de la app o parte del texto")
                    : qsTr("Las que descartes se guardan aquí")
            }
        }
    }
}
