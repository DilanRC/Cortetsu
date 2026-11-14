import QtQuick
import Quickshell
import "../services"
import "HubAnchor.js" as HubAnchor

// Hosts the Hub's edit mode (HubEditState) on the monitor being edited,
// loaded only while editing. A monitor that goes away takes its edit with it.
Scope {
    id: root

    readonly property var screen: CortetsuScreens.screens.find(screen => screen.name === HubEditState.monitor) ?? null
    readonly property var window: loader.item

    // The edit mode began: whatever else is open should close.
    signal begun()

    // Deferred: cancelling clears the monitor this binding reads, which
    // would re-enter it while it is still being notified (a binding loop).
    onScreenChanged: if (HubEditState.active && !screen)
        Qt.callLater(() => { if (HubEditState.active && !root.screen) HubEditState.cancel(); })

    Connections {
        target: HubEditState

        function onActiveChanged(): void {
            if (HubEditState.active)
                root.begun();
        }

        function onSaved(monitor: string, id: string): void {
            CortetsuToaster.toast(qsTr("Hub: %1").arg(HubAnchor.labels[id]),
                qsTr("En %1. Ajustes → Hub lo cambia o lo devuelve a la posición común.").arg(monitor), "open_with");
        }
    }

    LazyLoader {
        id: loader
        active: HubEditState.active && !!root.screen

        HubEditMode {
            readonly property var hub: CortetsuShellState.forScreen(root.screen)?.cortetsuState?.bottomHub ?? null
            screen: root.screen
            thickness: hub?.hubView.thickness ?? 56
            packedLength: hub?.hubView.packedLength ?? 600
        }
    }
}
