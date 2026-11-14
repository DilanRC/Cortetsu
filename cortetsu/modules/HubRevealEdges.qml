import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components/containers"
import "../services"
import "HubAnchor.js" as HubAnchor

// The edges an auto-hidden Hub comes back from, one per screen. A pointer
// thrown at the screen stops on its last pixel, but the Hub's own window sits
// inside the exclusive zones of the other surfaces (the border), short of that
// pixel. Each strip lies on the edge itself, past every zone, and its hover is
// the Hub's: it reveals the Hub and keeps it while the pointer rests there.
// Only while auto-hide is on: each layer window costs a GL context
// (Exclusions.qml).
Scope {
    id: root

    property bool enabled: false

    signal pointerEntered
    signal pointerExited

    Variants {
        // The edge is part of the model, so a new anchor gets a new strip: a
        // transparent surface never draws again, and its new anchors would
        // never be committed.
        model: root.enabled
            ? CortetsuScreens.screens.map(screen => ({ screen,
                edge: HubAnchor.describe(CortetsuConfig.bottomHub.anchorFor(screen?.name ?? "")).edge }))
            : []

        StyledWindow {
            id: strip

            required property var modelData
            readonly property string edge: modelData.edge
            readonly property bool vertical: edge === "left" || edge === "right"
            property bool inside: false

            screen: modelData.screen
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
                onPointerEntered: {
                    strip.inside = true;
                    root.pointerEntered();
                }
                onPointerExited: {
                    strip.inside = false;
                    root.pointerExited();
                }
            }

            // A strip replaced under the pointer gets no exit, and the Hub
            // would never hide again.
            Component.onDestruction: if (inside) root.pointerExited()
        }
    }
}
