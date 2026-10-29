pragma ComponentBehavior: Bound

import QtQuick
import "../../theme"

// What DashboardHost draws on its full-screen layer: the scrim, the panel and
// the ways to close it. It is an Item so the closing rules can be tested
// without a compositor.
FocusScope {
    id: root

    required property var screenState
    property bool open: false
    property var facePicker: null
    readonly property alias panel: dash
    readonly property alias pointerOnPanel: panelHover.hovered

    function close(): void {
        if (root.screenState)
            root.screenState.dashboard = false;
    }

    onOpenChanged: {
        if (root.open)
            root.forceActiveFocus();
    }

    Keys.onEscapePressed: event => {
        root.close();
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        visible: root.open
        color: Qt.alpha(CortetsuDesign.colorScrim, 0.34)
    }

    // A click outside the panel closes it, as in the launcher.
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.close()
    }

    Dash {
        id: dash
        anchors.centerIn: parent
        // 1180 x 620 when it fits, smaller at a higher scale or on a small screen.
        width: Math.min(implicitWidth, root.width - CortetsuDesign.spacingSection * 2)
        height: Math.min(implicitHeight, root.height - CortetsuDesign.spacingSection * 2)
        visible: root.open
        screenState: root.screenState
        facePicker: root.facePicker

        // Empty parts of the panel keep their clicks.
        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        // Hover open: leaving the panel closes it. Hover only ends after it
        // began, so the trip from the top edge to the panel keeps it open.
        HoverHandler {
            id: panelHover
            onHoveredChanged: if (!hovered && root.screenState?.dashboardOpenedBy === "hover") root.close()
        }
    }
}
