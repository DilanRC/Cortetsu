pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Qt.labs.folderlistmodel
import "."
import "../services"
import "CortetsuToplevels.js" as CortetsuToplevels
import "CortetsuFullscreen.js" as Fullscreen
import "CortetsuHyprActions.js" as HyprActions
import "CortetsuHyprEventPolicy.js" as HyprEventPolicy

// First-party Hyprland contract. Keep backend access in one adapter so
// consumers do not depend on inherited service names or implementation.
Singleton {
    id: root
    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua
    readonly property var focusedToplevel: Hyprland.activeToplevel
    readonly property var activeToplevel: isTaskbarToplevel(Hyprland.activeToplevel) ? Hyprland.activeToplevel : null
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1
    // A fullscreen window on the focused workspace: shortcuts and IPC do not
    // open guarded surfaces over it, and idle holds the screen. Derived from
    // focusedWorkspace: with Hyprland 0.56 (Lua) HyprlandMonitor.focused stays
    // false, so never look for the focused monitor through that property.
    readonly property bool focusedFullscreen: Fullscreen.hasFullscreen(focusedWorkspace?.toplevels.values.map(t => t.lastIpcObject))

    // Keyboard state has one reader. The layout follows Hyprland's
    // `activelayout` event; Caps Lock and Num Lock have no event, so they are
    // polled only while a visible consumer holds a watch.
    property bool keyboardKnown: false
    property bool capsLock: false
    property bool numLock: false
    property string kbLayout: ""
    property string kbLayoutFull: ""
    property string keyboardName: ""
    property int keyboardWatchers: 0
    // Layout changes arrive as the `activelayout` event. Lock keys have no event,
    // so their LEDs are read in-process; hyprctl runs only when one changes.
    readonly property bool lockToastsEnabled: CortetsuConfig.loaded
        && (CortetsuConfig.toastCapsLockChanged || CortetsuConfig.toastNumLockChanged)

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
        const name = String(keyboard.name ?? "");
        const sameKeyboard = keyboardKnown && keyboardName === name;
        const previousCapsLock = capsLock;
        const previousNumLock = numLock;
        const previousLayout = kbLayoutFull || kbLayout;
        const codes = String(keyboard.layout ?? "").split(",").map(code => code.trim());
        capsLock = keyboard.capsLock === true;
        numLock = keyboard.numLock === true;
        kbLayout = codes[Number(keyboard.active_layout_index ?? 0)] ?? codes[0] ?? "";
        kbLayoutFull = String(keyboard.active_keymap ?? "").trim();
        keyboardName = name;
        keyboardKnown = true;

        if (!sameKeyboard)
            return;
        if (CortetsuConfig.toastCapsLockChanged && previousCapsLock !== capsLock)
            CortetsuToaster.toast(qsTr("Caps Lock"), capsLock ? qsTr("Activado") : qsTr("Desactivado"), "keyboard_capslock");
        if (CortetsuConfig.toastNumLockChanged && previousNumLock !== numLock)
            CortetsuToaster.toast(qsTr("Num Lock"), numLock ? qsTr("Activado") : qsTr("Desactivado"), "keyboard_numlock");
        const layout = kbLayoutFull || kbLayout;
        if (CortetsuConfig.toastKbLayoutChanged && previousLayout && previousLayout !== layout)
            CortetsuToaster.toast(qsTr("Distribución del teclado"), layout, "keyboard");
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

    FolderListModel {
        id: leds
        folder: `file://${Quickshell.env("CORTETSU_SYSFS_ROOT") || "/sys"}/class/leds`
        showFiles: false
        // nameFilters do not apply to directories.
        function first(suffix: string): string {
            for (let i = 0; i < count; ++i)
                if (get(i, "fileName").endsWith(suffix))
                    return `${get(i, "filePath")}/brightness`;
            return "";
        }
    }

    // One reader per LED: reusing a FileView across paths returns stale text.
    // The first LED of each kind is read; the compositor mirrors lock state
    // to every keyboard, and hyprctl then reports the main one.
    FileView { id: capsLed; property string asked: ""; path: leds.count > 0 ? leds.first("::capslock") : ""; blockLoading: true; printErrors: false }
    FileView { id: numLed; property string asked: ""; path: leds.count > 0 ? leds.first("::numlock") : ""; blockLoading: true; printErrors: false }

    Timer {
        interval: 1000
        repeat: true
        running: root.lockToastsEnabled && (capsLed.path !== "" || numLed.path !== "")
        onTriggered: {
            // Ask the compositor only when a LED disagrees with the known state,
            // so no baseline is needed and a key without a LED is ignored.
            // A persistent disagreement (another keyboard's LED) asks once per
            // LED value, never every second.
            const differs = (led, known) => {
                if (led.path === "")
                    return false;
                led.reload();
                const text = led.text().trim();
                const asked = led.asked === text;
                led.asked = text;
                return text !== "" && !asked && (text !== "0") !== known;
            };
            if (!root.keyboardKnown)
                return;
            const capsDiffers = differs(capsLed, root.capsLock);
            const numDiffers = differs(numLed, root.numLock);
            if (capsDiffers || numDiffers)
                root.refreshKeyboard();
        }
    }

    // Quickshell never removes closed toplevels, and late events recreate them,
    // so the compositor's own list decides what is open. Null until the first
    // answer: nothing hidden. A failed probe keeps the last good list.
    property var liveAddresses: null
    property int clientsQueryCount: 0
    property int clientsQueryTotalMs: 0
    property int clientsQueryMaxMs: 0
    property real clientsQueryStartedAt: 0
    property int eventToplevelRefreshCalls: 0
    property int windowTitleRefreshCalls: 0

    function refreshClients(): void {
        if (!clientsProbe.running) {
            clientsQueryCount += 1;
            clientsQueryStartedAt = Date.now();
            clientsProbe.running = true;
        }
    }

    function finishClientsQuery(): void {
        if (clientsQueryStartedAt <= 0)
            return;
        const elapsed = Math.max(0, Date.now() - clientsQueryStartedAt);
        clientsQueryTotalMs += elapsed;
        clientsQueryMaxMs = Math.max(clientsQueryMaxMs, elapsed);
        clientsQueryStartedAt = 0;
    }

    function refreshToplevelsFromEvent(name: string): void {
        eventToplevelRefreshCalls += 1;
        if (name === "windowtitle")
            windowTitleRefreshCalls += 1;
        Hyprland.refreshToplevels();
    }

    function acceptClients(raw: string): void {
        liveAddresses = CortetsuToplevels.liveAddresses(raw) ?? liveAddresses;
    }

    // startup inventory: cortetsu:window-list (once at startup, then when a window opens or closes)
    Process {
        id: clientsProbe
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: root.acceptClients(text) }
        onExited: root.finishClientsQuery()
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

    function dispatchAction(action: var): bool {
        if (!action || typeof action.lua !== "string" || typeof action.legacy !== "string")
            return false;
        const request = usingLua ? action.lua : action.legacy;
        if (request.length === 0)
            return false;
        Hyprland.dispatch(request);
        return true;
    }

    function focusWorkspace(workspace: var): bool {
        return dispatchAction(HyprActions.focusWorkspace(workspace));
    }

    function toggleSpecialWorkspace(name: string): bool {
        return dispatchAction(HyprActions.toggleSpecialWorkspace(name));
    }

    function focusWindow(address: string): bool {
        return dispatchAction(HyprActions.focusWindow(address));
    }

    function closeWindow(address: string): bool {
        return dispatchAction(HyprActions.closeWindow(address));
    }

    function toggleFloat(address: string): bool {
        return dispatchAction(HyprActions.toggleFloat(address));
    }

    function togglePin(address: string): bool {
        return dispatchAction(HyprActions.togglePin(address));
    }

    function killWindow(address: string): bool {
        return dispatchAction(HyprActions.killWindow(address));
    }

    function moveWindow(address: string, workspace: var, follow: bool): bool {
        return dispatchAction(HyprActions.moveWindow(address, workspace, follow));
    }

    function moveCursor(x: real, y: real): bool {
        return dispatchAction(HyprActions.moveCursor(x, y));
    }

    function setDpms(on: bool): bool {
        return dispatchAction(HyprActions.dpms(on));
    }

    function exitHyprland(): bool {
        return dispatchAction(HyprActions.exit());
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
            const plan = HyprEventPolicy.refreshPlan(name);
            if (plan.refreshMonitors)
                Hyprland.refreshMonitors();
            if (plan.refreshWorkspaces)
                Hyprland.refreshWorkspaces();
            if (plan.refreshToplevels)
                root.refreshToplevelsFromEvent(name);
        }
    }
}
