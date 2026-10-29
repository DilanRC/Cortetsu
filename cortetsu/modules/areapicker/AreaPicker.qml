pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../../services"
import "../../components/containers"
import "../../components/misc"

Scope {
    id: root

    property bool active: false
    property bool freeze: false
    property bool closing: false
    property bool clipboardOnly: false

    onActiveChanged: CortetsuShellState.screenshotActive = active
    Component.onDestruction: CortetsuShellState.screenshotActive = false

    function open(freezeFrame: bool, copyToClipboard: bool): void {
        freeze = freezeFrame;
        clipboardOnly = copyToClipboard;
        closing = false;
        active = true;
    }

    function close(): void {
        closing = true;
        active = false;
    }

    // The capture the preview shows, its screen, and whether swappy has it.
    property string shot: ""
    property var shotScreen: null
    property bool editing: false
    property int shotRevision: 0
    property var pendingCapture: null

    // Private to the user: the helper creates it 0700 if missing.
    function shotDir(): string {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR");
        return runtime ? `${runtime}/cortetsu` : `${Quickshell.env("HOME")}/.cache/cortetsu`;
    }

    // Runs after the picker hides, so grim never captures its dimming layer.
    function capture(geometry: string, screen): void {
        pendingCapture = { geometry, screen, clipboard: clipboardOnly };
        captureTimer.restart();
    }

    // An action keeps the file it acts on: a new capture may replace `shot`
    // before it ends.
    function act(flag: string, path: string): void {
        if (!path || actions.running)
            return;
        actions.flag = flag;
        actions.target = path;
        actions.command = ["cortetsu-area-capture", flag, path];
        actions.running = true;
        editing = flag === "--edit";
    }

    function finish(flag: string, target: string, code: int, output: string): void {
        editing = false;
        const current = target === shot;
        if (code !== 0) {
            CortetsuToaster.toast(qsTr("Captura"), flag === "--edit"
                ? qsTr("No se pudo abrir el editor (swappy)")
                : qsTr("No se pudo completar la acción"), "error", 2);
            return;
        }
        if (flag === "--edit") {
            if (current)
                shotRevision++;
            else
                Quickshell.execDetached(["cortetsu-area-capture", "--save", target]);
            return;
        }
        if (current)
            shot = "";
        if (flag === "--copy") {
            CortetsuToaster.toast(qsTr("Captura copiada"), qsTr("Está en el portapapeles"), "content_copy");
            // Called from the action's exit: let the process settle first.
            Qt.callLater(() => act("--discard", target));
        } else if (flag === "--save") {
            CortetsuToaster.toast(qsTr("Captura guardada"), output.trim(), "save");
        }
    }

    Timer {
        id: captureTimer
        interval: 120
        onTriggered: {
            const request = root.pendingCapture;
            root.pendingCapture = null;
            if (!request || capturer.running)
                return;
            const path = `${root.shotDir()}/cortetsu-shot-${Quickshell.processId}-${Date.now()}.png`;
            capturer.request = { path, screen: request.screen, clipboard: request.clipboard };
            capturer.command = ["cortetsu-area-capture", request.geometry, path, ...(request.clipboard ? ["--clipboard"] : [])];
            capturer.running = true;
        }
    }

    Process {
        id: capturer
        property var request: null
        onExited: code => {
            const request = capturer.request;
            if (code !== 0) {
                CortetsuToaster.toast(qsTr("Captura"), qsTr("No se pudo hacer la captura"), "error", 2);
                return;
            }
            if (request.clipboard)
                return;
            // A capture still on screen is kept, not replaced. One an action
            // holds is left to that action (an edit saves it when it ends).
            if (root.shot && !(actions.running && actions.target === root.shot))
                Quickshell.execDetached(["cortetsu-area-capture", "--save", root.shot]);
            root.shot = request.path;
            root.shotScreen = request.screen;
        }
    }

    Process {
        id: actions
        property string flag: ""
        property string target: ""
        stdout: StdioCollector { id: actionOutput }
        onExited: code => root.finish(actions.flag, actions.target, code, actionOutput.text)
    }

    LazyLoader {
        // Hidden while a new area is chosen and captured, so the old card
        // never ends up inside the new image.
        active: !!root.shot && !root.editing && !!root.shotScreen
            && !root.active && !captureTimer.running && !capturer.running

        StyledWindow {
            screen: root.shotScreen
            name: "screenshot-preview"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // Mouse only: the preview never takes the keyboard from the app.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors.bottom: true
            anchors.right: true
            margins.bottom: 96
            margins.right: 16
            implicitWidth: preview.implicitWidth
            implicitHeight: preview.implicitHeight
            color: "transparent"

            ScreenshotPreview {
                id: preview
                anchors.fill: parent
                source: root.shot ? `file://${root.shot}?v=${root.shotRevision}` : ""
                busy: actions.running
                onCopyRequested: root.act("--copy", root.shot)
                onSaveRequested: root.act("--save", root.shot)
                onEditRequested: root.act("--edit", root.shot)
                onDiscardRequested: root.act("--discard", root.shot)
            }
        }
    }

    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            name: "area-picker"
            visible: root.active
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: empty }
            Picker { state: root; screen: win.modelData }
        }
    }

    IpcHandler {
        target: "picker"
        function open(): void { root.open(false, false); }
        function openFreeze(): void { root.open(true, false); }
        function openClip(): void { root.open(false, true); }
        function openFreezeClip(): void { root.open(true, true); }
    }

    CustomShortcut { name: "screenshot"; description: "Open screenshot tool"; onPressed: root.open(false, false) }
    CustomShortcut { name: "screenshotFreeze"; description: "Open screenshot tool (freeze mode)"; onPressed: root.open(true, false) }
    CustomShortcut { name: "screenshotClip"; description: "Open screenshot tool (clipboard)"; onPressed: root.open(false, true) }
    CustomShortcut { name: "screenshotFreezeClip"; description: "Open screenshot tool (freeze mode, clipboard)"; onPressed: root.open(true, true) }
}
