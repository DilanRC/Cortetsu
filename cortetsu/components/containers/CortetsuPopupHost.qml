import QtQuick
import Quickshell.Wayland
import "../../theme"

Item {
    id: root

    default property alias contentData: content.data
    property bool open: false
    property bool modal: true
    property bool dismissOnOutside: true
    property bool animate: true
    signal closed()

    anchors.fill: parent
    visible: open
    z: 100
    focus: open
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.98

    Rectangle {
        anchors.fill: parent
        visible: root.modal
        color: Qt.alpha(CortetsuDesign.colorScrim, CortetsuDesign.scrimOpacity)

        MouseArea {
            anchors.fill: parent
            enabled: root.dismissOnOutside
            onClicked: root.close()
        }
    }

    Item {
        id: content
        anchors.centerIn: parent
        z: 1
    }

    Binding {
        when: root.open
        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: WlrKeyboardFocus.OnDemand
    }

    Keys.onEscapePressed: root.close()

    Behavior on opacity {
        enabled: root.animate
        NumberAnimation { duration: CortetsuDesign.motionPanelMs; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        enabled: root.animate
        NumberAnimation { duration: CortetsuDesign.motionPanelMs; easing.type: Easing.OutCubic }
    }

    function close(): void {
        root.open = false;
        root.closed();
    }
}
