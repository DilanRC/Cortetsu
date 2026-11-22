pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../notifications" as NotificationComponents
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuOverlayPolicy.js" as OverlayPolicy
import "../settings" as SettingsModule

// The notification center (Premium sobria, 05-notifications). It is as tall
// as what it holds: a header, capsule filters when there is something to
// filter, the notifications on screen grouped by app, then the saved
// history. Nothing to show is one short empty state, not a tall panel.
//
// Where the screen is wide enough it adds a side column with do not
// disturb, private mode and the way to Ajustes; on a narrow screen the same
// controls sit in the header and the footer.
Item {
    id: root

    required property var screenState
    // The tallest the center may grow; past it the list scrolls.
    property real maxHeight: 900
    // Wide view: the side column fits next to the list.
    property bool wide: false
    property var activeNotifications: []
    // cortetsu-notifications keeps every notification not yet dismissed
    // (notifs.json, keyed by NotifData.key); those already loaded are listed
    // live. The saved list here is only what the file holds and this shell
    // has not loaded (another session's), so nothing is listed twice.
    readonly property var history: {
        const live = new Set(root.activeNotifications.map(item => String(item?.key ?? "")));
        return CortetsuNotifications.history.filter(entry => !live.has(String(entry.id)));
    }
    property string query: ""
    // "all" | "active" (still shown as a toast) | "earlier" (left the screen);
    // the saved list of another session shows under "all" only.
    property string filter: "all"
    // Groups the user folded, by app name.
    property var folded: ({})
    readonly property var filteredHistory: {
        const needle = root.query.trim().toLocaleLowerCase();
        if (needle.length === 0)
            return root.history;
        // Private mode searches who sent it only: matching the hidden text
        // would tell, through the count, what it says.
        return root.history.filter(entry => (CortetsuConfig.notificationPrivate ? [entry.appName] : [entry.summary, entry.body, entry.appName])
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
    readonly property bool hasActive: root.activeNotifications.length > 0
    readonly property bool hasHistory: root.history.length > 0
    // "active" keeps the ones still shown as a toast; "earlier" the rest.
    readonly property var shownNotifications: root.filter === "active"
        ? root.activeNotifications.filter(item => item?.popup)
        : root.filter === "earlier" ? root.activeNotifications.filter(item => !item?.popup)
        : root.activeNotifications
    readonly property int onScreenCount: root.activeNotifications.filter(item => item?.popup).length
    readonly property bool showActive: root.shownNotifications.length > 0
    readonly property bool showHistory: root.hasHistory && root.filter === "all"
    readonly property bool empty: !root.hasActive && !root.hasHistory
    readonly property int sideWidth: 268

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

    function toggleGroup(app: string): void {
        const next = Object.assign({}, root.folded);
        next[app] = !next[app];
        root.folded = next;
    }

    function openSettings(): void {
        SettingsModule.SettingsController.select("notifications");
        root.screenState.sidebar = false;
        OverlayPolicy.open(CortetsuShellState.allStates(), root.screenState, "settings");
    }

    implicitWidth: 420 + (root.wide ? root.sideWidth + CortetsuDesign.spacingStandard : 0)
    implicitHeight: Math.min(root.maxHeight, layout.implicitHeight + CortetsuDesign.spacingComfortable * 2)

    Component.onCompleted: refreshActiveNotifications()
    onOnScreenCountChanged: if (filter !== "all" && (onScreenCount === 0 || onScreenCount === activeNotifications.length)) filter = "all"

    Connections {
        target: Notifs
        // Deferred: a delegate destroyed by a model change unlocks its item,
        // which bumps `revision` again while the ListView is still applying
        // the model. callLater also folds a clear of N items into one update.
        function onRevisionChanged(): void { Qt.callLater(root.refreshActiveNotifications); }
    }

    RowLayout {
        id: layout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        ColumnLayout {
            id: mainColumn
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: CortetsuDesign.spacingStandard

            // --- Header ---------------------------------------------------
            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingStandard

                CortetsuEvolvingMark {
                    phase: "Ascended"
                    animated: false
                    monochrome: true
                    monochromeColor: CortetsuDesign.colorPrimary
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("Notificaciones")
                        textSize: CortetsuTypography.titleSmallPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        objectName: "notificationsSummary"
                        Layout.fillWidth: true
                        text: CortetsuNotifications.dnd ? qsTr("No molestar activo · los avisos llegan aquí sin aparecer")
                            : root.activeNotifications.length === 0 ? qsTr("Nada pendiente")
                            : root.activeNotifications.length === 1 ? qsTr("1 pendiente")
                            : qsTr("%1 pendientes").arg(root.activeNotifications.length)
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuNotifications.dnd ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                // Narrow view: do not disturb as a bell in the header.
                CortetsuButton {
                    objectName: "notificationsDndButton"
                    visible: !root.wide
                    compact: true
                    pill: true
                    active: CortetsuNotifications.dnd
                    icon: CortetsuNotifications.dnd ? "notifications_off" : "notifications"
                    label: ""
                    tooltipText: CortetsuNotifications.dnd ? qsTr("Desactivar No molestar")
                        : qsTr("No molestar: los avisos llegan aquí sin aparecer")
                    onClicked: CortetsuNotifications.setDnd(!CortetsuNotifications.dnd)
                }
            }

            // --- Filters: only with both kinds to tell apart (ADR-008, 5) --
            CortetsuTabBar {
                id: filters
                objectName: "notificationsFilters"
                Layout.fillWidth: true
                // fill makes its implicit width follow its width; a fixed
                // preference keeps the layout from chasing it.
                Layout.preferredWidth: 1
                // Only when it separates something: some still on screen as
                // a toast and some that already left it.
                visible: root.onScreenCount > 0 && root.onScreenCount < root.activeNotifications.length
                accessibleName: qsTr("Filtrar notificaciones")
                model: [
                    { label: qsTr("Todas · %1").arg(root.activeNotifications.length), icon: "notifications" },
                    { label: qsTr("En pantalla · %1").arg(root.onScreenCount), icon: "schedule" },
                    { label: qsTr("Anteriores · %1").arg(root.activeNotifications.length - root.onScreenCount), icon: "history" }
                ]
                currentIndex: ["all", "active", "earlier"].indexOf(root.filter)
                onSelected: index => root.filter = ["all", "active", "earlier"][index]
            }

            // History search, once the history is long enough to need it.
            CortetsuSearchBar {
                id: historySearch
                objectName: "notificationsSearch"
                Layout.fillWidth: true
                visible: root.showHistory && root.history.length > 8
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

            // --- The list: as tall as its content, then it scrolls --------
            Flickable {
                id: scroller
                objectName: "notificationsList"
                Layout.fillWidth: true
                visible: !root.empty
                // Everything around the list, so the list takes the rest.
                readonly property real chrome: CortetsuDesign.spacingComfortable * 2
                    + header.implicitHeight + footer.implicitHeight + CortetsuDesign.spacingStandard * 3
                    + (filters.visible ? filters.implicitHeight + CortetsuDesign.spacingStandard : 0)
                    + (historySearch.visible ? historySearch.implicitHeight + CortetsuDesign.spacingStandard : 0)
                Layout.preferredHeight: Math.min(listColumn.implicitHeight,
                    Math.max(CortetsuDesign.rowHeight * 2, root.maxHeight - chrome))
                contentHeight: listColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: listColumn
                    width: scroller.width
                    spacing: CortetsuDesign.spacingCompact

                    // On screen now, grouped by app.
                    Repeater {
                        objectName: "notificationsActive"
                        // Numeric model for QObject-backed notifications: a
                        // raw JS array binds the model to delegate creation.
                        model: root.showActive ? root.shownNotifications.length : 0
                        delegate: Column {
                            id: entry
                            required property int index
                            readonly property var item: root.shownNotifications[index]
                            readonly property string app: item?.appName ?? ""
                            readonly property bool firstOfGroup: index === 0
                                || (root.shownNotifications[index - 1]?.appName ?? "") !== app
                            readonly property bool groupFolded: !!root.folded[app]
                            width: listColumn.width
                            spacing: CortetsuDesign.spacingUnit

                            // The app once per group, with its count; the cards
                            // under it do not repeat it. A group folds, and an
                            // app can be muted from it (Ajustes lists them).
                            RowLayout {
                                readonly property bool muted: CortetsuConfig.mutedNotificationApps.includes(entry.app)
                                visible: entry.firstOfGroup
                                width: parent.width
                                spacing: CortetsuDesign.spacingCompact

                                CortetsuButton {
                                    compact: true
                                    pill: true
                                    icon: entry.groupFolded ? "expand_more" : "expand_less"
                                    label: (entry.app.length > 0 ? entry.app : qsTr("Sistema"))
                                        + ((root.groupCounts[entry.app] ?? 0) > 1 ? ` · ${root.groupCounts[entry.app]}` : "")
                                        + (parent.muted ? qsTr(" · silenciada") : "")
                                    tooltipText: entry.groupFolded ? qsTr("Mostrar el grupo") : qsTr("Plegar el grupo")
                                    onClicked: root.toggleGroup(entry.app)
                                }

                                Item { Layout.fillWidth: true }

                                CortetsuButton {
                                    visible: entry.app.length > 0
                                    compact: true
                                    icon: parent.muted ? "notifications_active" : "notifications_off"
                                    label: ""
                                    tooltipText: parent.muted ? qsTr("Volver a mostrar los avisos de %1").arg(entry.app)
                                        : qsTr("Silenciar %1: sus avisos llegarán aquí sin aparecer").arg(entry.app)
                                    onClicked: CortetsuConfig.setNotificationAppMuted(entry.app, !parent.muted)
                                }
                            }

                            NotificationComponents.Notification {
                                visible: !entry.groupFolded
                                focus: entry.index === 0
                                width: parent.width
                                modelData: entry.item
                                props: ({})
                                expanded: false
                                screenState: root.screenState
                            }
                        }
                    }

                    // Saved history: what was dismissed or expired, kept by
                    // cortetsu-notifications until cleared.
                    CortetsuSectionHeader {
                        visible: root.showHistory
                        width: listColumn.width
                        title: qsTr("Guardadas en otra sesión")
                        detail: root.query.length > 0 ? qsTr("%1 de %2").arg(root.filteredHistory.length).arg(root.history.length)
                            : root.history.length === 1 ? qsTr("1 guardada") : qsTr("%1 guardadas").arg(root.history.length)
                    }

                    Repeater {
                        objectName: "notificationsHistory"
                        // A long history shows its newest 100; search reaches the rest.
                        model: root.showHistory ? root.filteredHistory.slice(0, 100) : []
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool urgent: (modelData.urgency ?? 0) >= 2
                            width: listColumn.width
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
                                    text: row.urgent ? "priority_high" : "history"
                                    iconSize: CortetsuTypography.iconSmallPx
                                    color: row.urgent ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                                }

                                ColumnLayout {
                                    id: texts
                                    Layout.fillWidth: true
                                    spacing: 0
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: CortetsuConfig.notificationPrivate ? qsTr("Contenido oculto")
                                            : (row.modelData.summary || qsTr("Notificación"))
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
                    }

                    CortetsuText {
                        visible: root.showHistory && root.filteredHistory.length === 0 && root.query.length > 0
                        width: listColumn.width
                        text: qsTr("Nada coincide con «%1»").arg(root.query)
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }

            // One empty state, short, for an empty center.
            CortetsuStateMessage {
                objectName: "notificationsEmpty"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                visible: root.empty
                kind: "empty"
                title: qsTr("Sin notificaciones")
                detail: qsTr("Los avisos se quedan aquí hasta que los descartes")
            }

            // --- Footer --------------------------------------------------
            RowLayout {
                id: footer
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuButton {
                    objectName: "notificationsClear"
                    visible: !root.empty
                    compact: true
                    icon: "delete_sweep"
                    label: qsTr("Borrar todo")
                    tooltipText: qsTr("Descarta todas; no se guardan")
                    onClicked: {
                        CortetsuNotifications.clear();
                        Notifs.clear();
                    }
                }

                Item { Layout.fillWidth: true }

                CortetsuButton {
                    visible: !root.wide
                    compact: true
                    icon: "settings"
                    label: qsTr("Ajustes")
                    onClicked: root.openSettings()
                }
            }
        }

        // --- Side column (wide view) --------------------------------------
        ColumnLayout {
            objectName: "notificationsSide"
            visible: root.wide
            Layout.preferredWidth: root.sideWidth
            Layout.minimumWidth: root.sideWidth
            Layout.maximumWidth: root.sideWidth
            Layout.alignment: Qt.AlignTop
            spacing: CortetsuDesign.spacingStandard

            SideCard {
                objectName: "notificationsDnd"
                Layout.fillWidth: true
                icon: CortetsuNotifications.dnd ? "do_not_disturb_on" : "do_not_disturb_off"
                title: qsTr("No molestar")
                detail: CortetsuNotifications.dnd ? qsTr("Llegan aquí sin aparecer en pantalla")
                    : qsTr("Los avisos nuevos aparecen en pantalla")
                checked: CortetsuNotifications.dnd
                onToggled: checked => CortetsuNotifications.setDnd(checked)
            }

            SideCard {
                objectName: "notificationsPrivate"
                Layout.fillWidth: true
                icon: CortetsuConfig.notificationPrivate ? "visibility_off" : "visibility"
                title: qsTr("Modo privado")
                detail: qsTr("Muestra quién avisa, no lo que dice")
                checked: CortetsuConfig.notificationPrivate
                onToggled: checked => CortetsuConfig.notificationPrivate = checked
            }

            SideCard {
                Layout.fillWidth: true
                icon: "tune"
                title: qsTr("Ajustes de notificaciones")
                detail: qsTr("Duración, apps silenciadas y pantalla completa")
                link: true
                onActivated: root.openSettings()
            }
        }
    }
}
