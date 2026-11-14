import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components/containers"

// The edge an auto-hidden Hub comes back from. A pointer thrown at the screen
// stops on its last pixel, but the Hub's own window sits inside the exclusive
// zones of the other surfaces (the border), short of that pixel. This strip
// lies on the edge itself, past every zone, and its hover is the Hub's: it
// reveals the Hub and keeps it while the pointer rests there.
StyledWindow {
    id: root

    // "top", "bottom", "left" or "right" (HubAnchor.describe).
    required property string edge
    readonly property bool vertical: edge === "left" || edge === "right"

    signal pointerEntered
    signal pointerExited

    name: "hub-reveal"
    anchors.top: edge === "top" || vertical
    anchors.bottom: edge === "bottom" || vertical
    anchors.left: edge === "left" || !vertical
    anchors.right: edge === "right" || !vertical
    implicitWidth: 3
    implicitHeight: 3
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    CortetsuBottomHubHoverTarget {
        anchors.fill: parent
        onPointerEntered: root.pointerEntered()
        onPointerExited: root.pointerExited()
    }
}
