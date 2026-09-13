pragma ComponentBehavior: Bound

import ".."
import QtQuick
import Quickshell
import QtQuick.Controls
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../../components"

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool overviewVisible

    property int selectedIndex: -1

    readonly property var clients: {
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
                return special || ws.id > 0;
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

    readonly property string windowCountText:
        clients.length === 1
            ? qsTr("1 ventana")
            : qsTr("%1 ventanas").arg(clients.length)

    readonly property string monitorCountText:
        monitorCount === 1
            ? qsTr("1 pantalla")
            : qsTr("%1 pantallas").arg(monitorCount)

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

    function selectorFor(client): string {
        const address = addressOf(client);
        return address ? `address:${address}` : "";
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

        const selector =
            selectorFor(client);

        const ws =
            client.workspace;

        screenState.cortetsuState?.setRetained("overview", false);

        Qt.callLater(() => {
            if (ws) {
                if (CortetsuHypr.usingLua) {
                    const workspaceValue =
                        ws.name?.startsWith("special:")
                            ? `"${ws.name}"`
                            : ws.id;

                    CortetsuHypr.dispatch(
                        `hl.dsp.focus({ workspace = ${workspaceValue} })`
                    );
                } else {
                    const target =
                        ws.name?.startsWith("special:")
                            ? ws.name
                            : ws.id;

                    CortetsuHypr.dispatch(
                        `workspace ${target}`
                    );
                }
            }

            if (selector) {
                CortetsuHypr.dispatch(
                    CortetsuHypr.usingLua
                        ? `hl.dsp.focus({ window = "${selector}" })`
                        : `focuswindow ${selector}`
                );
            }
        });
    }

    function activateWorkspace(id): void {
        screenState.cortetsuState?.setRetained("overview", false);

        Qt.callLater(() => {
            CortetsuHypr.dispatch(
                CortetsuHypr.usingLua
                    ? `hl.dsp.focus({ workspace = ${id} })`
                    : `workspace ${id}`
            );
        });
    }

    function closeClient(client): void {
        const selector =
            selectorFor(client);

        if (!selector)
            return;

        CortetsuHypr.dispatch(
            CortetsuHypr.usingLua
                ? `hl.dsp.window.close({ window = "${selector}" })`
                : `closewindow ${selector}`
        );
    }

    function toggleFloating(client): void {
        const selector =
            selectorFor(client);

        if (!selector)
            return;

        CortetsuHypr.dispatch(
            CortetsuHypr.usingLua
                ? `hl.dsp.window.float({ action = "toggle", window = "${selector}" })`
                : `togglefloating ${selector}`
        );
    }

    function moveClientToWorkspace(client, workspaceId): void {
        const selector =
            selectorFor(client);

        if (!selector || workspaceId <= 0)
            return;

        CortetsuHypr.dispatch(
            CortetsuHypr.usingLua
                ? `hl.dsp.window.move({ workspace = ${workspaceId}, follow = false, window = "${selector}" })`
                : `movetoworkspacesilent ${workspaceId},${selector}`
        );
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

        Rectangle {
            id: header

            // Super+Tab is a window switcher. The old title bar duplicated
            // information and consumed the most valuable vertical space.
            visible: false
            height: 0

            width: parent.width
            implicitHeight: 0

            radius:
                CortetsuDesign.radiusLarge

            /*
             * Local header scrim only: keeps the title legible over a busy
             * wallpaper without bringing back the giant opaque overview panel.
             */
            color:
                Qt.alpha(
                    CortetsuDesign.colorSurfaceHigh,
                    0.78
                )

            border.width: 1

            border.color:
                Qt.alpha(
                    CortetsuDesign.colorOutlineVariant,
                    0.70
                )

            Row {
                id: headerRow

                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                spacing: 12

                CortetsuIcon {
                    anchors.verticalCenter:
                        parent.verticalCenter

                    text: "view_cozy"

                    color:
                        CortetsuDesign.colorPrimary

                    iconSize: CortetsuTypography.iconExtraLargePx
                }

                Column {
                    anchors.verticalCenter:
                        parent.verticalCenter

                    spacing: -1

                    CortetsuText {
                        text: qsTr("Vista general")

                        textSize: CortetsuTypography.titleLargePx
                    }

                    CortetsuText {
                        text:
                            `${root.windowCountText} · ${root.monitorCountText}`

                        color:
                            CortetsuDesign.colorOutline

                        textSize: CortetsuTypography.labelMediumPx
                    }
                }

                Item {
                    width:
                        Math.max(
                            20,
                            parent.width - 710
                        )

                    height: 1
                }

                Rectangle {
                    anchors.verticalCenter:
                        parent.verticalCenter

                    implicitWidth:
                        hints.implicitWidth + 22

                    implicitHeight: 34

                    radius:
                        999

                    color:
                        Qt.alpha(
                            CortetsuDesign.colorSurface,
                            0.90
                        )

                    border.width: 1

                    border.color:
                        Qt.alpha(
                            CortetsuDesign.colorOutlineVariant,
                            0.78
                        )

                    CortetsuText {
                        id: hints

                        anchors.centerIn: parent

                        text:
                            qsTr(
                                "Flechas mover · Enter/Espacio enfocar · Supr cerrar · F flotar"
                            )

                        color:
                            CortetsuDesign.colorOnSurfaceVariant

                        textSize: CortetsuTypography.labelMediumPx
                    }
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

        Rectangle {
            visible: false
            width: parent.width
            height: 1

            color:
                Qt.alpha(
                    CortetsuDesign.colorOutlineVariant,
                    0.62
                )
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
                icon: "web_asset_off"
                title: qsTr("No hay ventanas para mostrar")
                detail: qsTr("Abre una aplicación para verla aquí")
            }
        }
    }
}
