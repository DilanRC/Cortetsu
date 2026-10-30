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
        if (root.open) {
            root.forceActiveFocus();
        }
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
        // Always the same zone: hanging from the top edge, centred. It drops
        // a little from the edge as it fades in. 1040 x 580 when it fits.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: CortetsuDesign.spacingStandard + drop
        property real drop: root.open ? 0 : -24
        width: Math.min(implicitWidth, root.width - CortetsuDesign.spacingSection * 2)
        height: Math.min(implicitHeight, root.height - CortetsuDesign.spacingSection * 2 - 72)
        visible: root.open
        focus: true
        screenState: root.screenState
        facePicker: root.facePicker
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic } }
        // design-lint: allow motion-layout-property: the panel drops from the top edge it hangs from
        Behavior on drop { NumberAnimation { duration: CortetsuDesign.motionStandardMs * 1.6; easing.type: Easing.OutQuint } }

        // Empty parts of the panel keep their clicks.
        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        HoverHandler { id: panelHover }
    }
}
