pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "CortetsuToplevels.js" as CortetsuToplevels

// First-party Hyprland contract. Keep backend access in one adapter so
// consumers do not depend on inherited service names or implementation.
Singleton {
    id: root
    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua
    readonly property var activeToplevel: isTaskbarToplevel(Hyprland.activeToplevel) ? Hyprland.activeToplevel : null
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1
    // A fullscreen window on the focused workspace: shortcuts and IPC do not
    // open guarded surfaces over it (SurfaceRegistry fullscreenGuard).
    readonly property bool focusedFullscreen: focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    // Keyboard state has one reader. The layout follows Hyprland's
    // `activelayout` event; Caps Lock and Num Lock have no event, so they are
    // polled only while a visible consumer holds a watch.
    property bool keyboardKnown: false
    property bool capsLock: false
    property bool numLock: false
    property string kbLayout: ""
    property string kbLayoutFull: ""
    property int keyboardWatchers: 0

    function watchKeyboard(): void { keyboardWatchers += 1; refreshKeyboard(); }
    function unwatchKeyboard(): void { keyboardWatchers = Math.max(0, keyboardWatchers - 1); }

    function refreshKeyboard(): void {
        if (!keyboardProbe.running)
            keyboardProbe.running = true;
    }

    function acceptKeyboardState(raw: string): void {
        let keyboard = null;
        try {
            const keyboards = JSON.parse(raw)?.keyboards ?? [];
            keyboard = keyboards.find(device => device.main) ?? keyboards[0] ?? null;
        } catch (_) {}
        if (!keyboard) {
            keyboardKnown = false;
            return;
        }
        const codes = String(keyboard.layout ?? "").split(",").map(code => code.trim());
        capsLock = keyboard.capsLock === true;
        numLock = keyboard.numLock === true;
        kbLayout = codes[Number(keyboard.active_layout_index ?? 0)] ?? codes[0] ?? "";
        kbLayoutFull = String(keyboard.active_keymap ?? "").trim();
        keyboardKnown = true;
    }

    Component.onCompleted: {
        refreshKeyboard();
        refreshClients();
    }

    // startup inventory: cortetsu:keyboard-state (once at startup, then on demand)
    Process {
        id: keyboardProbe
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { onStreamFinished: root.acceptKeyboardState(text) }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.keyboardWatchers > 0
        onTriggered: root.refreshKeyboard()
    }

    // Quickshell never removes closed toplevels, and late events recreate them,
    // so the compositor's own list decides what is open. Null until the first
    // answer: nothing hidden. A failed probe keeps the last good list.
    property var liveAddresses: null

    function refreshClients(): void {
        if (!clientsProbe.running)
            clientsProbe.running = true;
    }

    function acceptClients(raw: string): void {
        liveAddresses = CortetsuToplevels.liveAddresses(raw) ?? liveAddresses;
    }

    // startup inventory: cortetsu:window-list (once at startup, then when a window opens or closes)
    Process {
        id: clientsProbe
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: root.acceptClients(text) }
    }

    // One probe per burst of window events. A probe already in flight may
    // predate the change, so the timer waits for it and asks again.
    Timer {
        id: clientsProbeDelay
        interval: 40
        onTriggered: {
            if (clientsProbe.running)
                restart();
            else
                root.refreshClients();
        }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged(): void { clientsProbeDelay.restart(); }
    }

    function dispatch(request: string): void {
        Hyprland.dispatch(request)
    }

    function monitorFor(screen): var {
        const name = screen?.name ?? "";
        return Hyprland.monitors.values.find(monitor => monitor.name === name) ?? null;
    }

    function isTaskbarToplevel(client): bool {
        if (!client)
            return false;
        const window = client.lastIpcObject ?? {};
        const windowClass = window.class ?? "";
        const initialClass = window.initialClass ?? "";
        const title = window.title ?? "";
        const initialTitle = window.initialTitle ?? "";
        // Hyprland can retain an unmapped helper surface briefly after its
        // owner closes. It must not become a taskbar or overview item.
        if (window.mapped === false)
            return false;
        if (!CortetsuToplevels.isLive(liveAddresses, client.address))
            return false;
        if (Number.isFinite(Number(window.pid)) && Number(window.pid) <= 0)
            return false;
        if ((window.xwayland ?? false) && !windowClass && !title)
            return false;
        if (/^(QtWebEngineProcess\.exe|QtWebEngineProcess)$/.test(windowClass) || /^(QtWebEngineProcess\.exe|QtWebEngineProcess)$/.test(initialClass))
            return false;
        return !/^(Wine System Tray|System Tray|Qt Tray Icon Window|TrayWindow|win[0-9]+)$/i.test(title)
            && !/^(Wine System Tray|System Tray|Qt Tray Icon Window|TrayWindow|win[0-9]+)$/i.test(initialTitle);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            const name = event.name;
            if (name === "openwindow" || name === "closewindow")
                clientsProbeDelay.restart();
            if (name === "activelayout")
                root.refreshKeyboard();
            if (name.endsWith("v2"))
                return;
            if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(name)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(name)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (name.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (name.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (name.includes("window") || name.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(name)) {
                Hyprland.refreshToplevels();
            }
        }
    }
}
