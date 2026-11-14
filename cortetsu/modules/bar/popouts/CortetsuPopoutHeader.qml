pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../.."
import "../../settings"
import "../../CortetsuOverlayPolicy.js" as OverlayPolicy

// The top line every service popout shares: what it is and how it stands,
// the service's own switch when there is one, and the way to its full page
// in Settings. Level 1 of the progressive depth (ADR-008): frequent
// operations here, everything else one step away.
RowLayout {
    id: root

    property string title: ""
    property string detail: ""
    // Settings page id (PageRegistry); empty hides the link.
    property string settingsPage: ""
    // The popout's PopoutState, closed when Settings opens.
    property var popouts: null
    default property alias trailing: slot.data

    Layout.fillWidth: true
    spacing: CortetsuDesign.spacingCompact

    function openSettings(): void {
        const state = CortetsuShellState.forActive();
        SettingsController.select(root.settingsPage);
        root.popouts?.close();
        if (state)
            Qt.callLater(() => OverlayPolicy.open(CortetsuShellState.allStates(), state, "settings"));
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: root.title
        detail: root.detail
    }

    RowLayout {
        id: slot
        spacing: CortetsuDesign.spacingCompact
    }

    CortetsuButton {
        objectName: "popoutSettings"
        visible: root.settingsPage.length > 0
        compact: true
        icon: "open_in_new"
        label: ""
        tooltipText: qsTr("Abrir en Ajustes")
        Accessible.name: qsTr("Abrir %1 en Ajustes").arg(root.title)
        onClicked: root.openSettings()
    }
}
