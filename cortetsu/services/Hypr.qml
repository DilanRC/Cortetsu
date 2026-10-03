pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../modules"

// Compatibility surface for upstream modules while migration continues.
// All backend access is owned by CortetsuHypr and Quickshell.Hyprland.
Singleton {
    id: root

    readonly property var toplevels: CortetsuHypr.toplevels
    readonly property var workspaces: CortetsuHypr.workspaces
    readonly property var monitors: CortetsuHypr.monitors
    readonly property bool usingLua: CortetsuHypr.usingLua
    readonly property var activeToplevel: CortetsuHypr.activeToplevel
    readonly property var focusedWorkspace: CortetsuHypr.focusedWorkspace
    readonly property var focusedMonitor: CortetsuHypr.focusedMonitor
    readonly property int activeWsId: CortetsuHypr.activeWsId
    readonly property bool keyboardKnown: CortetsuHypr.keyboardKnown
    readonly property bool capsLock: CortetsuHypr.capsLock
    readonly property bool numLock: CortetsuHypr.numLock
    readonly property string defaultKbLayout: "??"
    readonly property string kbLayoutFull: CortetsuHypr.kbLayoutFull
    readonly property string kbLayout: CortetsuHypr.kbLayout
    readonly property var options: ({})
    readonly property var extras: QtObject {
        function batchMessage(messages): void {
            for (const message of messages)
                Hyprland.dispatch(message);
        }
        function refreshOptions(): void {}
    }

    function dispatch(request: string): void { CortetsuHypr.dispatch(request); }
    function monitorFor(screen): var { return CortetsuHypr.monitorFor(screen); }
    function toplevelsForWs(ws: int): list<var> {
        return toplevels.values.filter(t => t.workspace && t.workspace.id === ws && isTaskbarToplevel(t));
    }
    function isTaskbarToplevel(client): bool { return CortetsuHypr.isTaskbarToplevel(client); }
    function isToplevelIgnored(toplevel): bool { return !toplevel?.lastIpcObject?.mapped; }
}
