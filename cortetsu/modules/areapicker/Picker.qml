pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

MouseArea {
    id: root

    required property var state
    required property ShellScreen screen
    property bool onClient: false
    readonly property bool recording: !state.regionHandler && state.mode === "record"
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
    readonly property real dragThreshold: 8

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
        const left = Math.max(0, Math.min(screen.width, rsx));
        const top = Math.max(0, Math.min(screen.height, rsy));
        const right = Math.max(left, Math.min(screen.width, rsx + sw));
        const bottom = Math.max(top, Math.min(screen.height, rsy + sh));
        const x = Math.round(screen.x + left);
        const y = Math.round(screen.y + top);
        const width = Math.round(right - left);
        const height = Math.round(bottom - top);
        if (width <= 0 || height <= 0) {
            close();
            return;
        }
        if (root.state.regionHandler) {
            root.state.returnRegion({ output: screen.name, x: Math.round(left), y: Math.round(top), w: width, h: height });
            close();
            return;
        }
        close();
        if (root.recording)
            root.state.record(`${width}x${height}+${x}+${y}`);
        else
            root.state.capture(`${x},${y} ${width}x${height}`, root.screen);
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
        sx = event.x;
        sy = event.y;
        ex = event.x;
        ey = event.y;
        onClient = false;
    }
    onReleased: event => {
        if (Math.abs(event.x - ssx) < root.dragThreshold
                && Math.abs(event.y - ssy) < root.dragThreshold) {
            root.checkClientRects(event.x, event.y);
            if (!root.onClient) {
                root.sx = 0;
                root.sy = 0;
                root.ex = root.screen.width;
                root.ey = root.screen.height;
            }
        }
        root.capture();
    }
    onPositionChanged: event => {
        if (pressed) {
            sx = ssx;
            sy = ssy;
            ex = event.x;
            ey = event.y;
        } else if (!root.state.freeze) {
            checkClientRects(event.x, event.y);
        }
    }
    Keys.onEscapePressed: root.close()
    Keys.onTabPressed: if (!root.state.regionHandler) root.state.mode = root.recording ? "capture" : "record"
    Keys.onPressed: event => {
        if (event.key === Qt.Key_S && root.recording) {
            root.state.recordSound = !root.state.recordSound;
            event.accepted = true;
        }
    }

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
        border.color: root.recording ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
    }

    CortetsuText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: CortetsuDesign.spacingComfortable
        text: root.recording ? qsTr("Selecciona el área que quieres grabar") : root.state.regionHandler ? qsTr("Selecciona el área que quieres compartir") : root.state.freeze ? qsTr("Selecciona un área para capturar") : qsTr("Selecciona un área")
        textSize: CortetsuTypography.bodyLargePx
        color: CortetsuDesign.colorOnSurface
    }

    // Capture / record switch. Hidden while choosing a share region, which
    // has its own purpose. Tab switches, S toggles sound while recording.
    Row {
        id: modeSwitch
        visible: !root.state.regionHandler
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: CortetsuDesign.spacingSection * 3
        spacing: CortetsuDesign.spacingStandard

        Rectangle {
            width: modes.implicitWidth + 8
            height: 44
            radius: height / 2
            color: Qt.alpha(CortetsuDesign.colorSurface, 0.92)
            border.width: 1
            border.color: Qt.alpha(CortetsuDesign.colorOnSurface, 0.08)

            Row {
                id: modes
                anchors.centerIn: parent
                Repeater {
                    model: [{ mode: "capture", label: qsTr("Captura"), icon: "screenshot_region" },
                            { mode: "record", label: qsTr("Grabar"), icon: "radio_button_checked" }]
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool selected: root.state.mode === modelData.mode
                        width: chipRow.implicitWidth + 28
                        height: 36
                        radius: height / 2
                        color: selected ? (modelData.mode === "record" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary) : "transparent"
                        Behavior on color { ColorAnimation { duration: CortetsuDesign.motionStandardMs } }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            CortetsuIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.icon
                                color: chip.selected ? (chip.modelData.mode === "record" ? CortetsuDesign.colorWashi : CortetsuDesign.colorOnPrimary) : CortetsuDesign.colorOnSurface
                            }
                            CortetsuText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.label
                                color: chip.selected ? (chip.modelData.mode === "record" ? CortetsuDesign.colorWashi : CortetsuDesign.colorOnPrimary) : CortetsuDesign.colorOnSurface
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: event => event.accepted = true
                            onClicked: root.state.mode = chip.modelData.mode
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: root.recording
            width: 44
            height: 44
            radius: height / 2
            color: root.state.recordSound ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorSurface, 0.92)
            CortetsuIcon {
                anchors.centerIn: parent
                text: root.state.recordSound ? "mic" : "mic_off"
                color: root.state.recordSound ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: event => event.accepted = true
                onClicked: root.state.recordSound = !root.state.recordSound
            }
        }
    }
}
