pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

MouseArea {
    id: root

    required property var state
    required property ShellScreen screen
    property bool onClient: false
    property real realBorderWidth: 2
    property real realRounding: 0
    property real ssx
    property real ssy
    property real sx: 0
    property real sy: 0
    property real ex: screen.width
    property real ey: screen.height
    property real rsx: Math.min(sx, ex)
    property real rsy: Math.min(sy, ey)
    property real sw: Math.abs(sx - ex)
    property real sh: Math.abs(sy - ey)

    readonly property var clients: {
        const monitor = CortetsuHypr.monitorFor(screen);
        if (!monitor)
            return [];
        const special = monitor.lastIpcObject.specialWorkspace;
        const workspaceId = special?.name ? special.id : monitor.activeWorkspace?.id;
        return CortetsuHypr.toplevels.values.filter(client => client?.workspace?.id === workspaceId).sort((a, b) => {
            const ac = a.lastIpcObject ?? {};
            const bc = b.lastIpcObject ?? {};
            return (bc.pinned - ac.pinned) || ((bc.fullscreen !== 0) - (ac.fullscreen !== 0)) || (bc.floating - ac.floating);
        });
    }

    function checkClientRects(x: real, y: real): void {
        for (const client of clients) {
            const data = client?.lastIpcObject;
            if (!data)
                continue;
            const cx = data.at[0] - screen.x;
            const cy = data.at[1] - screen.y;
            const cw = data.size[0];
            const ch = data.size[1];
            if (cx <= x && cy <= y && cx + cw >= x && cy + ch >= y) {
                onClient = true;
                sx = cx;
                sy = cy;
                ex = cx + cw;
                ey = cy + ch;
                return;
            }
        }
        onClient = false;
    }

    function capture(): void {
        const x = Math.ceil(screen.x + rsx);
        const y = Math.ceil(screen.y + rsy);
        const width = Math.floor(sw);
        const height = Math.floor(sh);
        if (width <= 0 || height <= 0) {
            close();
            return;
        }
        const path = `/tmp/cortetsu-picker-${Quickshell.processId}-${Date.now()}.png`;
        const geometry = `${x},${y} ${width}x${height}`;
        const command = ["cortetsu-area-capture", geometry, path];
        if (root.state.clipboardOnly)
            command.push("--clipboard");
        Quickshell.execDetached(command);
        close();
    }

    function close(): void { root.state.close(); }

    anchors.fill: parent
    opacity: root.state.active ? 1 : 0
    hoverEnabled: true
    cursorShape: Qt.CrossCursor
    focus: true

    Component.onCompleted: {
        const client = clients[0];
        if (client) {
            const data = client.lastIpcObject;
            sx = data.at[0] - screen.x;
            sy = data.at[1] - screen.y;
            ex = sx + data.size[0];
            ey = sy + data.size[1];
            onClient = true;
        } else {
            sx = screen.width / 2 - 100;
            sy = screen.height / 2 - 100;
            ex = screen.width / 2 + 100;
            ey = screen.height / 2 + 100;
        }
    }

    onPressed: event => {
        ssx = event.x;
        ssy = event.y;
        onClient = false;
    }
    onReleased: root.capture()
    onPositionChanged: event => {
        if (pressed) {
            sx = ssx;
            sy = ssy;
            ex = event.x;
            ey = event.y;
        } else {
            checkClientRects(event.x, event.y);
        }
    }
    Keys.onEscapePressed: root.close()

    Rectangle {
        anchors.fill: parent
        color: CortetsuDesign.colorSecondaryContainer
        opacity: 0.3
        layer.enabled: true
        layer.effect: CortetsuMask { maskSource: selectionWrapper; maskInverted: true }
    }

    Item {
        id: selectionWrapper
        anchors.fill: parent
        visible: false
        Rectangle { x: root.rsx; y: root.rsy; width: root.sw; height: root.sh; radius: root.realRounding }
    }

    Rectangle {
        x: root.rsx - root.realBorderWidth
        y: root.rsy - root.realBorderWidth
        width: root.sw + root.realBorderWidth * 2
        height: root.sh + root.realBorderWidth * 2
        color: "transparent"
        radius: root.realRounding > 0 ? root.realRounding + root.realBorderWidth : 0
        border.width: root.realBorderWidth
        border.color: CortetsuDesign.colorPrimary
    }

    CortetsuText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: CortetsuDesign.spacingComfortable
        text: root.state.freeze ? qsTr("Select an area to capture") : qsTr("Select an area")
        textSize: CortetsuTypography.bodyLargePx
        color: CortetsuDesign.colorOnSurface
    }
}
