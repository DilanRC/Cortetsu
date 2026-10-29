pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components/containers"
import "../theme"
import "prompt" as Prompt
import "."

// Password and confirmation dialogs for native helpers: cortetsu-prompter
// (keyring and GPG, desktop-runtime-rs/src/prompter.rs) and cortetsu-agents
// (Wi-Fi and Bluetooth, src/agents.rs). A helper opens a private socket per
// dialog and calls `qs ipc call secretprompt request <socket> <token>`. This
// scope connects, shows each prompt line it reads and writes one answer line
// back. The helper closes the socket when its client is done, which closes
// the dialog. Passwords only cross that socket, never `qs ipc`.
Scope {
    id: root

    property var queue: []
    property string token: ""
    // The current prompt line, or null between connecting and the first one.
    property var prompt: null
    property bool waiting: false
    // Escape while the client checks an answer: there is no prompt to cancel
    // yet, so the client's next prompt (after a wrong password) is refused.
    property bool cancelPending: false
    property var requestScreen: null
    // Fixtures turn the window off and drive the protocol only.
    property bool dialogEnabled: true
    // Fixtures also leave the system's Wi-Fi and Bluetooth agents alone.
    property bool agentsEnabled: true

    function activeScreen(): var {
        const monitor = CortetsuHypr.focusedMonitor;
        return CortetsuScreens.screens.find(screen => CortetsuHypr.monitorFor(screen) === monitor)
            ?? CortetsuScreens.screens[0] ?? null;
    }

    function request(socketPath: string, requestToken: string): void {
        if (socketPath.length === 0 || requestToken.length === 0)
            return;
        root.queue = root.queue.concat([{ socketPath, token: requestToken }]);
        root.next();
    }

    function next(): void {
        if (root.token.length > 0 || root.queue.length === 0)
            return;
        const item = root.queue[0];
        root.queue = root.queue.slice(1);
        root.token = item.token;
        socket.path = item.socketPath;
        socket.connected = true;
    }

    function received(line: string): void {
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
        if (root.cancelPending) {
            root.cancelPending = false;
            root.prompt = data;
            root.waiting = false;
            root.answer(false, "", false, "");
            return;
        }
        if (!root.prompt)
            root.requestScreen = root.activeScreen();
        root.waiting = false;
        root.prompt = data;
    }

    function answer(accepted: bool, password: string, choice: bool, identity: string): void {
        if (!root.prompt)
            return;
        if (root.waiting) {
            if (!accepted)
                root.cancelPending = true;
            return;
        }
        root.waiting = true;
        socket.write(JSON.stringify({ token: root.token, reply: accepted ? "yes" : "no", password, choice, identity }) + "\n");
        socket.flush();
    }

    // The helper closed the socket: the client is done with this dialog.
    function closed(): void {
        root.token = "";
        root.prompt = null;
        root.waiting = false;
        root.cancelPending = false;
        Qt.callLater(root.next);
    }

    // This side gives up on the dialog (a foreign token).
    function finish(): void {
        // Clear the token first, so the disconnect below does not re-enter.
        root.token = "";
        socket.connected = false;
        root.closed();
    }

    Socket {
        id: socket
        parser: SplitParser {
            onRead: line => root.received(line)
        }
        // Never set `connected` from these: Quickshell 0.3.2 crashes in
        // Socket::onSocketError if the error handler disconnects the socket.
        onConnectedChanged: if (!connected && root.token.length > 0) root.closed()
        onError: if (root.token.length > 0) root.closed()
    }

    // Unplugging the dialog's monitor would leave the prompt with no window.
    Connections {
        target: CortetsuScreens
        function onScreensChanged(): void {
            if (root.prompt && !CortetsuScreens.screens.includes(root.requestScreen))
                root.requestScreen = root.activeScreen();
        }
    }

    LazyLoader {
        active: root.dialogEnabled && !!root.prompt && !!root.requestScreen

        StyledWindow {
            screen: root.requestScreen
            name: "secret-prompt"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Rectangle { anchors.fill: parent; color: Qt.alpha(CortetsuDesign.colorScrim, 0.72) }

            Prompt.SecretPrompt {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 48)
                prompt: root.prompt
                waiting: root.waiting
                focus: true
                onAnswered: (accepted, password, choice, identity) => root.answer(accepted, password, choice, identity)
            }
        }
    }

    // NetworkManager's secret agent and BlueZ's pairing agent. The helper
    // dies with the shell; if it stops on its own (a crash, or the system bus
    // restarting), it is started again after a pause.
    // startup inventory: cortetsu:agents
    Process {
        id: agents
        command: [`${Quickshell.env("HOME")}/.local/bin/cortetsu-agents`]
        running: root.agentsEnabled
        stderr: SplitParser {
            onRead: line => console.info(line)
        }
        onExited: (code, status) => {
            if (root.agentsEnabled)
                agentsRestart.restart();
        }
    }

    Timer {
        id: agentsRestart
        interval: 5000
        onTriggered: agents.running = root.agentsEnabled
    }

    IpcHandler {
        target: "secretprompt"
        // cortetsu-prompter checks this before taking the D-Bus name.
        function ping(): string {
            return "ok";
        }
        function request(socketPath: string, token: string): void {
            root.request(socketPath, token);
        }
    }
}
