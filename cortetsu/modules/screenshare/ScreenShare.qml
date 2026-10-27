pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Screencast picker for xdg-desktop-portal-hyprland. `cortetsu-share-picker`
// (desktop-runtime-rs/src/sharepicker.rs) opens a private socket and calls
// `qs ipc call screenshare request <socket> <token>`. This scope connects,
// reads the offered windows, shows ScreenSharePicker and writes one answer
// line back. The helper composes the xdph selection, so a reply can only name
// an output or a window that was offered.
Scope {
    id: root

    // modules/areapicker/AreaPicker.qml, for the Region tab.
    property var areaPicker: null

    // idle -> connecting -> choosing (-> region) -> idle
    property string phase: "idle"
    property string token: ""
    property var windows: []
    property var queue: []

    readonly property bool choosing: phase === "choosing"

    function request(socketPath: string, requestToken: string): void {
        if (socketPath.length === 0 || requestToken.length === 0)
            return;
        root.queue = root.queue.concat([{ socketPath, token: requestToken }]);
        root.next();
    }

    function next(): void {
        if (root.phase !== "idle" || root.queue.length === 0)
            return;
        const item = root.queue[0];
        root.queue = root.queue.slice(1);
        root.token = item.token;
        root.windows = [];
        root.phase = "connecting";
        socket.path = item.socketPath;
        socket.connected = true;
    }

    function received(line: string): void {
        if (root.phase !== "connecting")
            return;
        let data = null;
        try {
            data = JSON.parse(line);
        } catch (e) {
            data = null;
        }
        if (!data || data.token !== root.token) {
            root.finish();
            return;
        }
        root.windows = Array.isArray(data.windows) ? data.windows : [];
        root.phase = "choosing";
    }

    function reply(answer: var): void {
        if (root.phase === "idle")
            return;
        if (socket.connected) {
            socket.write(JSON.stringify(Object.assign({ token: root.token }, answer)) + "\n");
            socket.flush();
        }
        root.finish();
    }

    function shareScreen(output: string, remember: bool): void {
        root.reply({ type: "screen", output, remember });
    }

    function shareWindow(handle: int, remember: bool): void {
        root.reply({ type: "window", handle, remember });
    }

    function cancel(): void {
        root.reply({ type: "cancel" });
    }

    // Hands the screen over to the area picker; its answer, or a cancel,
    // goes straight back to the helper.
    function pickRegion(remember: bool): void {
        if (!root.areaPicker) {
            root.cancel();
            return;
        }
        root.phase = "region";
        root.areaPicker.pickRegion(region => {
            if (!region)
                root.cancel();
            else
                root.reply({ type: "region", output: region.output, x: region.x, y: region.y,
                    w: region.w, h: region.h, remember });
        });
    }

    function finish(): void {
        // Idle first, so the disconnect below does not re-enter finish().
        root.phase = "idle";
        socket.connected = false;
        root.token = "";
        root.windows = [];
        Qt.callLater(root.next);
    }

    Socket {
        id: socket
        parser: SplitParser {
            onRead: line => root.received(line)
        }
        // The helper gave up (timeout or xdph cancelled the request).
        onConnectedChanged: if (!connected && root.phase !== "idle") root.finish()
        onError: if (root.phase !== "idle") root.finish()
    }

    // The overlay window exists only while a choice is pending: no GL
    // context or capture cost at rest. Fixtures turn it off.
    property bool pickerEnabled: true
    LazyLoader {
        active: root.pickerEnabled && root.choosing
        ScreenSharePicker {
            controller: root
        }
    }

    IpcHandler {
        target: "screenshare"
        function request(socketPath: string, token: string): void {
            root.request(socketPath, token);
        }
    }
}
