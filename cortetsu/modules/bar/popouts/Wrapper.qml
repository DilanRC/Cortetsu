pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property ShellScreen screen
    required property real offsetScale

    readonly property alias content: content
    readonly property alias nexus: nexus
    readonly property real nonAnimWidth: children.find(c => c.shouldBeActive)?.implicitWidth ?? content.implicitWidth
    readonly property real nonAnimHeight: children.find(c => c.shouldBeActive)?.implicitHeight ?? content.implicitHeight
    readonly property Item current: (content.item as Content)?.current ?? null
    readonly property bool isDetached: detachedMode.length > 0
    readonly property bool pointerInside: popupHover.hovered && bottomAttached && hasCurrent && !closing

    property alias currentName: popoutState.currentName
    property alias hasCurrent: popoutState.hasCurrent
    property real currentCenter
    property string detachedMode
    property string queuedMode
    property bool bottomAttached
    property bool closing
    property real bottomOffset: 54
    property real bottomRightMargin: 4
    property real bottomAnchorCenter: -1

    property int animLength: 0
    property var animCurve

    function setAnims(detach: bool): void {
        animLength = detach ? 220 : 160;
        animCurve = Easing.OutCubic;
    }

    function cancelClose(): void {
        closeTimer.stop();
        closing = false;
    }

    function detach(mode: string): void {
        cancelClose();
        hasCurrent = true;
        bottomAttached = false;
        bottomAnchorCenter = -1;
        setAnims(true);
        if (mode === "winfo") {
            queuedMode = "";
            detachedMode = mode;
        } else {
            queuedMode = mode;
            detachedMode = "any";
        }
        setAnims(false);
        focus = true;
    }

    function close(): void {
        if (bottomAttached && hasCurrent) {
            closing = true;
            closeTimer.restart();
            return;
        }
        hasCurrent = false;
        detachedMode = "";
        bottomAttached = false;
        bottomAnchorCenter = -1;
    }

    Timer {
        id: closeTimer
        interval: CortetsuDesign.motionFastMs
        repeat: false
        onTriggered: {
            root.hasCurrent = false;
            root.detachedMode = "";
            root.bottomAttached = false;
            root.bottomAnchorCenter = -1;
            root.closing = false;
        }
    }

    onHasCurrentChanged: {
        if (hasCurrent) {
            cancelClose();
            root.forceActiveFocus();
            Qt.callLater(() => root.forceActiveFocus());
            return;
        }
        if (bottomAttached && !closing) {
            // Hover/click state can clear the popout directly. Keep its anchor
            // alive long enough for the close animation to return to the icon.
            hasCurrent = true;
            closing = true;
            closeTimer.restart();
            return;
        }
        if (!hasCurrent) {
            bottomAttached = false;
            bottomAnchorCenter = -1;
        }
    }

    onPointerInsideChanged: {
        if (pointerInside)
            CortetsuShellState.enterAttachedPopup(root);
        else
            CortetsuShellState.leaveAttachedPopup(root);
    }

    Component.onDestruction: CortetsuShellState.leaveAttachedPopup(root)

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight
    focus: hasCurrent

    HoverHandler {
        id: popupHover
        enabled: root.hasCurrent && root.bottomAttached && !root.closing
    }

    Keys.onEscapePressed: {
        if (currentName === "wirelesspassword" && content.item) {
            const passwordPopout = (content.item as Content)?.children.find(c => c.name === "wirelesspassword");
            if (passwordPopout && passwordPopout.item) {
                passwordPopout.item.closeDialog();
                return;
            }
        }
        close();
    }

    Keys.onPressed: event => {
        if (currentName === "wirelesspassword")
            event.accepted = false;
    }

    PopoutState {
        id: popoutState
        onDetachRequested: mode => root.detach(mode)
    }

    HyprlandFocusGrab {
        active: root.isDetached
        windows: [QsWindow.window]
        onCleared: root.close()
    }

    Binding {
        when: root.isDetached || (root.hasCurrent && root.currentName === "wirelesspassword")
        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.Exclusive
    }

    Comp {
        id: content
        shouldBeActive: root.hasCurrent && !root.detachedMode
        anchors.fill: parent
        sourceComponent: Content { popouts: popoutState }
    }

    Comp {
        id: nexus
        shouldBeActive: root.detachedMode === "any"
        anchors.centerIn: parent
        sourceComponent: CortetsuDetachedPopup {
            mode: root.queuedMode
            popouts: root
        }
    }

    Behavior on implicitWidth { NumberAnimation { duration: root.animLength; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight {
        enabled: root.offsetScale < 1
        NumberAnimation { duration: root.animLength; easing.type: Easing.OutCubic }
    }

    component Comp: Loader {
        id: comp
        property bool shouldBeActive
        active: false
        opacity: 0
        states: State {
            name: "active"
            when: comp.shouldBeActive
            PropertyChanges { comp.opacity: 1; comp.active: true }
        }
        transitions: [
            Transition {
                from: ""; to: "active"
                SequentialAnimation {
                    PropertyAction { property: "active" }
                    NumberAnimation { property: "opacity"; duration: comp.parent.animLength; easing.type: Easing.OutCubic }
                }
            },
            Transition {
                from: "active"; to: ""
                SequentialAnimation {
                    NumberAnimation { property: "opacity"; duration: comp.parent.animLength; easing.type: Easing.OutCubic }
                    PropertyAction { property: "active" }
                }
            }
        ]
    }
}
