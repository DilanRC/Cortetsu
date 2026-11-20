pragma ComponentBehavior: Bound

import ".."
import QtQuick
import Quickshell
import QtQuick.Controls
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "OverviewKeys.js" as OverviewKeys
import "../../components"

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool overviewVisible
    // Open or still fading out. While hidden the window list is not tracked:
    // every open, close and move would rebuild cards nobody sees.
    property bool tracking: true

    property int selectedIndex: -1
    // Filter typed after / or Ctrl+F: matches title, class and app id. The F
    // key alone keeps toggling floating, so the filter opens on its own key.
    property string filter: ""
    property bool filtering: false

    function matchesFilter(client): bool {
        const needle = root.filter.trim().toLowerCase();
        if (!needle)
            return true;
        const ipc = client.lastIpcObject ?? {};
        return `${client.title ?? ""} ${ipc.class ?? ""} ${ipc.initialClass ?? ""} ${ipc.initialTitle ?? ""}`
            .toLowerCase().includes(needle);
    }

    function startFilter(): void {
        root.filtering = true;
        Qt.callLater(() => filterField.forceActiveFocus());
    }

    function endFilter(): void {
        filterField.text = "";
        root.filtering = false;
        root.forceActiveFocus();
    }

    readonly property var clients: {
        if (!root.tracking)
            return [];
        const values =
            CortetsuHypr.toplevels.values.filter(c => {
                if (!CortetsuHypr.isTaskbarToplevel(c))
                    return false;

                const ws = c.workspace;
                if (!ws)
                    return false;

                const special =
                    ws.name?.startsWith("special:") ?? false;

                /*
                 * Normal Hyprland workspaces are positive IDs.
                 * A taskbar toplevel reporting workspace 0 is normally an
                 * orphan/helper surface during state transitions and should
                 * not become a real overview card.
                 */
                return (special || ws.id > 0) && root.matchesFilter(c);
            });

        return [...values].sort((a, b) => {
            const aws = a.workspace?.id ?? 2147483647;
            const bws = b.workspace?.id ?? 2147483647;

            if (aws !== bws)
                return aws - bws;

            return (a.title ?? "").localeCompare(
                b.title ?? ""
            );
        });
    }

    readonly property var currentClient:
        selectedIndex >= 0 &&
        selectedIndex < clients.length
            ? clients[selectedIndex]
            : null

    readonly property int monitorCount:
        CortetsuScreens.screens.length

    /*
     * Adaptive overview grid:
     * 1 window  -> one large card
     * 2         -> two large cards
     * 3         -> three balanced cards
     * 4         -> 2x2
     * 5-6       -> three columns
     * 7+        -> four columns on wide screens
     *
     * This removes the huge dead area that the workspace-grouped layout
     * produced with only a few windows open.
     */
    readonly property int idealColumns: {
        const n = clients.length;

        if (n <= 1)
            return 1;
        if (n === 2)
            return 2;
        if (n === 3)
            return 3;
        if (n === 4)
            return 2;
        if (n <= 6)
            return 3;

        return 4;
    }

    readonly property int maxColumnsByWidth:
        width >= 1450 ? 4 :
        width >= 1040 ? 3 : 2

    readonly property int gridColumns:
        Math.max(
            1,
            Math.min(
                idealColumns,
                maxColumnsByWidth,
                Math.max(1, clients.length)
            )
        )

    readonly property real cardGap: 16

    readonly property real maxCardWidth: {
        const n = clients.length;

        if (n <= 1)
            return 980;

        if (n === 2)
            return 710;

        if (n === 3)
            return 540;

        if (gridColumns === 2)
            return 640;

        if (gridColumns === 3)
            return 500;

        return 410;
    }

    readonly property real cardWidth:
        Math.min(
            maxCardWidth,
            Math.max(
                250,
                (
                    windowViewport.width -
                    cardGap * (gridColumns - 1) -
                    8
                ) /
                gridColumns
            )
        )

    readonly property real windowGridWidth:
        cardWidth * gridColumns +
        cardGap * (gridColumns - 1)

    function addressOf(client): string {
        return client?.lastIpcObject?.address ?? "";
    }

    function windowCountForWorkspace(id): int {
        return clients.filter(
            c => c.workspace?.id === id
        ).length;
    }

    function workspaceIdsForScreen(shellScreen, fallbackIndex): var {
        const mon = CortetsuScreens.monitorFor(shellScreen);
        const name = mon?.name ?? "";

        let start = fallbackIndex * 10 + 1;

        if (name === "eDP-1")
            start = 1;
        else if (name === "HDMI-A-1")
            start = 11;

        const result = [];

        for (let i = 0; i < 10; ++i)
            result.push(start + i);

        return result;
    }

    function selectClient(client): void {
        if (!client)
            return;

        const address = addressOf(client);

        const idx =
            clients.findIndex(
                c => addressOf(c) === address
            );

        if (idx >= 0)
            selectedIndex = idx;
    }

    function selectInitialClient(): void {
        if (clients.length === 0) {
            selectedIndex = -1;
            return;
        }

        const activeAddress =
            addressOf(CortetsuHypr.activeToplevel);

        const idx =
            clients.findIndex(
                c => addressOf(c) === activeAddress
            );

        selectedIndex =
            idx >= 0 ? idx : 0;
    }

    function moveSelection(delta): void {
        if (clients.length === 0)
            return;

        let idx = selectedIndex;

        if (idx < 0)
            idx = 0;
        else
            idx =
                (
                    idx +
                    delta +
                    clients.length
                ) %
                clients.length;

        selectedIndex = idx;
    }

    function activateClient(client): void {
        if (!client)
            return;

        const address = addressOf(client);

        const ws =
            client.workspace;

        screenState.cortetsuState?.setRetained("overview", false);

        Qt.callLater(() => {
            if (ws) {
                const target = ws.name?.startsWith("special:") ? ws.name : ws.id;
                CortetsuHypr.focusWorkspace(target);
            }

            if (address)
                CortetsuHypr.focusWindow(address);
        });
    }

    function activateWorkspace(id): void {
        screenState.cortetsuState?.setRetained("overview", false);

        Qt.callLater(() => {
            CortetsuHypr.focusWorkspace(id);
        });
    }

    function closeClient(client): void {
        const address = addressOf(client);

        if (!address)
            return;

        CortetsuHypr.closeWindow(address);
    }

    function toggleFloating(client): void {
        const address = addressOf(client);

        if (!address)
            return;

        CortetsuHypr.toggleFloat(address);
    }

    function moveClientToWorkspace(client, workspaceId): void {
        const address = addressOf(client);

        if (!address || workspaceId <= 0)
            return;

        CortetsuHypr.moveWindow(address, workspaceId, false);
    }

    // Digits address this screen's ten workspaces in rail order
    // (OverviewKeys.js): a plain digit opens the workspace, Alt+digit sends
    // the selected window there and keeps the overview open, the keyboard
    // counterpart of dropping a card on a workspace.
    function screenWorkspaceIds(): var {
        return workspaceIdsForScreen(root.screen, Math.max(0, Quickshell.screens.indexOf(root.screen)));
    }

    function ensureSelectedVisible(): void {
        if (
            selectedIndex < 0 ||
            selectedIndex >= windowRepeater.count
        )
            return;

        const item =
            windowRepeater.itemAt(selectedIndex);

        if (!item)
            return;

        const point =
            item.mapToItem(
                windowViewport.contentItem,
                0,
                0
            );

        const top = point.y;
        const bottom =
            top + item.height;

        if (top < windowViewport.contentY) {
            windowViewport.contentY =
                Math.max(
                    0,
                    top - 16
                );
        } else if (
            bottom >
            windowViewport.contentY +
                windowViewport.height
        ) {
            windowViewport.contentY =
                Math.max(
                    0,
                    Math.min(
                        windowViewport.contentHeight -
                            windowViewport.height,
                        bottom -
                            windowViewport.height +
                            16
                    )
                );
        }
    }

    function openOverview(): void {
        filterField.text = "";
        root.filtering = false;
        selectInitialClient();
        forceActiveFocus();

        Qt.callLater(
            ensureSelectedVisible
        );
    }

    onOverviewVisibleChanged: {
        if (overviewVisible)
            Qt.callLater(openOverview);
    }

    onSelectedIndexChanged:
        Qt.callLater(
            ensureSelectedVisible
        )

    onClientsChanged: {
        if (clients.length === 0)
            selectedIndex = -1;
        else if (
            selectedIndex >= clients.length
        )
            selectedIndex =
                clients.length - 1;
        else if (selectedIndex < 0)
            selectInitialClient();
    }

    focus: true

    Keys.onEscapePressed:
        screenState.cortetsuState?.setRetained("overview", false)

    Keys.onLeftPressed:
        moveSelection(-1)

    Keys.onRightPressed:
        moveSelection(1)

    Keys.onUpPressed:
        moveSelection(-gridColumns)

    Keys.onDownPressed:
        moveSelection(gridColumns)

    Keys.onReturnPressed:
        activateClient(currentClient)

    Keys.onEnterPressed:
        activateClient(currentClient)

    Keys.onSpacePressed:
        activateClient(currentClient)

    Keys.onDeletePressed:
        closeClient(currentClient)

    Keys.onPressed: event => {
        if (
            event.key === Qt.Key_Tab &&
            !(event.modifiers & Qt.ShiftModifier)
        ) {
            moveSelection(1);
            event.accepted = true;
            return;
        }

        if (
            event.key === Qt.Key_Backtab ||
            (
                event.key === Qt.Key_Tab &&
                (event.modifiers & Qt.ShiftModifier)
            )
        ) {
            moveSelection(-1);
            event.accepted = true;
            return;
        }

        if (
            event.key === Qt.Key_Slash ||
            (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))
        ) {
            startFilter();
            event.accepted = true;
            return;
        }

        const digit = OverviewKeys.digitAction(event.key, event.modifiers, screenWorkspaceIds());
        if (digit.action === "move") {
            if (currentClient)
                moveClientToWorkspace(currentClient, digit.workspace);
            event.accepted = true;
            return;
        }
        if (digit.action === "open") {
            activateWorkspace(digit.workspace);
            event.accepted = true;
            return;
        }

        if (
            event.key === Qt.Key_F &&
            !(event.modifiers & Qt.ControlModifier)
        ) {
            toggleFloating(currentClient);
            event.accepted = true;
        }
    }

    /*
     * Fullscreen close target behind all visual content.
     * ContentWindow already provides the dark scrim, so v2 avoids a giant
     * opaque rectangle and lets the wallpaper remain part of the composition.
     */
    MouseArea {
        anchors.fill: parent

        onClicked:
            root.screenState.cortetsuState?.setRetained("overview", false)
    }

    Column {
        id: layout

        anchors.fill: parent

        anchors.topMargin: 24
        anchors.bottomMargin: 24
        anchors.leftMargin: 38
        anchors.rightMargin: 38

        spacing: 0

        // The window filter. It takes no room until / or Ctrl+F opens it.
        Item {
            id: header
            width: parent.width
            height: root.filtering ? filterField.implicitHeight + 16 : 0
            visible: root.filtering

            CortetsuSearchBar {
                id: filterField
                objectName: "overviewFilter"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: Math.min(440, parent.width)
                compact: true
                placeholderText: qsTr("Filtrar ventanas por título o aplicación")
                Accessible.name: placeholderText
                onTextChanged: root.filter = text
                // Escape belongs to the field while it is open: the first
                // empties it, the second hands the keys back to the grid.
                Keys.onShortcutOverride: event => event.accepted = event.key === Qt.Key_Escape
                Keys.onEscapePressed: event => {
                    if (text.length > 0)
                        text = "";
                    else
                        root.endFilter();
                    event.accepted = true;
                }
                Keys.onDownPressed: root.forceActiveFocus()
                Keys.onReturnPressed: {
                    root.selectInitialClient();
                    root.activateClient(root.currentClient);
                }
                Keys.onEnterPressed: {
                    root.selectInitialClient();
                    root.activateClient(root.currentClient);
                }
            }
        }

        /*
         * Compact monitor/workspace rail.
         * It is capped on a single monitor so it no longer stretches a tiny
         * set of controls over the entire width of the display.
         */
        Item {
            id: monitorRailHost

            visible: false

            width: parent.width

            height: 0

            Flow {
                id: monitorRail

                anchors.horizontalCenter:
                    parent.horizontalCenter

                width:
                    root.monitorCount === 1
                        ? Math.min(
                            monitorRailHost.width,
                            930
                        )
                        : monitorRailHost.width

                height:
                    childrenRect.height

                spacing: 10

                Repeater {
                    model: CortetsuScreens.screens

                    Rectangle {
                        id: monitorBox

                        required property ShellScreen modelData
                        required property int index

                        readonly property var monitor:
                            CortetsuScreens.monitorFor(modelData)

                        readonly property var workspaceIds:
                            root.workspaceIdsForScreen(
                                modelData,
                                index
                            )

                        width:
                            (
                                monitorRail.width -
                                monitorRail.spacing *
                                    Math.max(
                                        0,
                                        root.monitorCount - 1
                                    )
                            ) /
                            Math.max(
                                1,
                                root.monitorCount
                            )

                        implicitHeight: 68

                        radius:
                            CortetsuDesign.radiusLarge

                        color:
                            Qt.alpha(
                                CortetsuDesign.colorSurfaceHigh,
                                0.90
                            )

                        border.width: 1

                        border.color:
                            Qt.alpha(
                                CortetsuDesign.colorOutlineVariant,
                                0.82
                            )

                        Row {
                            anchors.fill: parent
                            anchors.margins: 9

                            spacing: 10

                            Row {
                                width: 116

                                anchors.verticalCenter:
                                    parent.verticalCenter

                                spacing: 7

                                CortetsuIcon {
                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    text:
                                        monitorBox.monitor?.name ===
                                            "eDP-1"
                                        ? "laptop"
                                        : "desktop_windows"

                                    color:
                                        CortetsuDesign.colorPrimary

                                    iconSize: CortetsuTypography.iconMediumPx
                                }

                                Column {
                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    CortetsuText {
                                        text:
                                            monitorBox.monitor?.name ??
                                            qsTr("Pantalla")

                                        textSize: CortetsuTypography.labelLargePx
                                    }

                                    CortetsuText {
                                        text:
                                            monitorBox.monitor
                                                ?.activeWorkspace
                                                ?.id
                                            ? `activa · ${monitorBox.monitor.activeWorkspace.id}`
                                            : ""

                                        color:
                                            CortetsuDesign.colorOutline

                                        textSize: CortetsuTypography.labelSmallPx
                                    }
                                }
                            }

                            Row {
                                id: chips

                                width:
                                    parent.width - 126

                                anchors.verticalCenter:
                                    parent.verticalCenter

                                spacing: 4

                                Repeater {
                                    model:
                                        monitorBox.workspaceIds

                                    Rectangle {
                                        id: chip

                                        required property int modelData

                                        readonly property int workspaceId:
                                            modelData

                                        readonly property int windowCount:
                                            root.windowCountForWorkspace(
                                                workspaceId
                                            )

                                        readonly property bool activeWorkspace:
                                            monitorBox.monitor
                                                ?.activeWorkspace
                                                ?.id ===
                                            workspaceId

                                        width:
                                            (
                                                chips.width -
                                                chips.spacing * 9
                                            ) /
                                            10

                                        implicitHeight: 36

                                        radius:
                                            CortetsuDesign.radiusMedium

                                        color:
                                            dropZone.containsDrag
                                            ? CortetsuDesign.colorSecondaryContainer
                                            : activeWorkspace
                                                ? CortetsuDesign.colorSecondaryContainer
                                                : workspaceMouse
                                                    .containsMouse
                                                    ? CortetsuDesign.colorSurfaceHigh
                                                    : "transparent"

                                        border.width:
                                            dropZone.containsDrag
                                                ? 2
                                                : 0

                                        border.color:
                                            CortetsuDesign.colorTertiary

                                        Column {
                                            anchors.centerIn:
                                                parent

                                            spacing: -2

                                            CortetsuText {
                                                anchors.horizontalCenter:
                                                    parent.horizontalCenter

                                                text:
                                                    `${chip.workspaceId}`

                                                textSize: CortetsuTypography.labelMediumPx

                                                color:
                                                    chip.activeWorkspace
                                                    ? CortetsuDesign.colorOnSecondaryContainer
                                                    : CortetsuDesign.colorOnSurfaceVariant
                                            }

                                            CortetsuText {
                                                visible:
                                                    chip.windowCount > 0

                                                anchors.horizontalCenter:
                                                    parent.horizontalCenter

                                                text:
                                                    chip.windowCount === 1
                                                    ? "1 win"
                                                    : `${chip.windowCount} wins`

                                                textSize: CortetsuTypography.labelSmallPx

                                                color:
                                                    CortetsuDesign.colorOutline
                                            }
                                        }

                                        MouseArea {
                                            id: workspaceMouse

                                            anchors.fill: parent

                                            hoverEnabled: true

                                            cursorShape:
                                                Qt.PointingHandCursor

                                            onClicked:
                                                root.activateWorkspace(
                                                    chip.workspaceId
                                                )
                                        }

                                        DropArea {
                                            id: dropZone

                                            z: 5

                                            anchors.fill: parent

                                            keys:
                                                ["overview-window"]

                                            onDropped: drop => {
                                                const source =
                                                    drop.source;

                                                if (source?.client) {
                                                    root.moveClientToWorkspace(
                                                        source.client,
                                                        chip.workspaceId
                                                    );

                                                    drop
                                                        .acceptProposedAction();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        /*
         * One adaptive grid for ALL windows.
         * Workspace identity stays on each card and in the workspace rail.
         * This gives much better balance when only 2-4 windows are open.
         */
        Flickable {
            id: windowViewport

            width: parent.width

            height:
                Math.max(
                    180,
                    layout.height -
                        header.height -
                        monitorRailHost.height
                )

            contentWidth: width

            contentHeight:
                Math.max(
                    height,
                    windowGrid.height + 28
                )

            clip: true

            boundsBehavior:
                Flickable.StopAtBounds

            ScrollBar.vertical:
                ScrollBar {
                    policy:
                        windowViewport.contentHeight >
                            windowViewport.height
                        ? ScrollBar.AsNeeded
                        : ScrollBar.AlwaysOff
                }

            MouseArea {
                id: viewportBackground

                z: -1
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton

                onClicked:
                    root.screenState.cortetsuState?.setRetained("overview", false)
            }

            Grid {
                id: windowGrid

                x:
                    Math.max(
                        0,
                        (
                            windowViewport.width -
                            width
                        ) /
                        2
                    )

                y:
                    clients.length <= gridColumns
                        ? Math.max(
                            10,
                            (
                                windowViewport.height -
                                height
                            ) /
                            2 -
                            2
                        )
                        : 10

                width:
                    root.windowGridWidth

                columns:
                    root.gridColumns

                columnSpacing:
                    root.cardGap

                rowSpacing:
                    root.cardGap

                Repeater {
                    id: windowRepeater

                    model: root.clients

                    WindowCard {
                        id: card

                        required property var modelData

                        client: modelData

                        screen: root.screen

                        overviewVisible:
                            root.overviewVisible

                        selected:
                            root.addressOf(card.client) ===
                            root.addressOf(
                                root.currentClient
                            )

                        width:
                            root.cardWidth

                        onActivate:
                            client =>
                                root.activateClient(
                                    client
                                )

                        onCloseRequested:
                            client =>
                                root.closeClient(
                                    client
                                )

                        onToggleFloatingRequested:
                            client =>
                                root.toggleFloating(
                                    client
                                )

                        onSelectRequested:
                            client =>
                                root.selectClient(
                                    client
                                )
                    }
                }
            }

            CortetsuStateMessage {
                anchors.centerIn: parent

                width: 300
                visible:
                    root.clients.length === 0
                icon: root.filter.length > 0 ? "search_off" : "web_asset_off"
                title: root.filter.length > 0 ? qsTr("Ninguna ventana coincide con «%1»").arg(root.filter)
                    : qsTr("No hay ventanas para mostrar")
                detail: root.filter.length > 0 ? qsTr("Escape vacía el filtro")
                    : qsTr("Abre una aplicación para verla aquí")
            }
        }
    }
}
