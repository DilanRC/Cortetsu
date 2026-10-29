import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"

Item {
    id: root

    default property alias contentData: content.data
    property bool open: false
    property bool modal: true
    property bool dismissOnOutside: true
    property bool animate: true
    // System prompts (share picker, polkit) take the keyboard outright.
    property int keyboardFocus: WlrKeyboardFocus.OnDemand
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

    // Sized by its child: an empty Item put the panel's corner, not its
    // centre, at the middle of the screen.
    Item {
        id: content
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
        z: 1
    }

    Binding {
        when: root.open
        target: QsWindow.window
        property: "WlrLayershell.keyboardFocus"
        value: root.keyboardFocus
    }

    Keys.onEscapePressed: root.close()

    // A modal dialog is a popover: it enters in motionPopoverMs from the
    // centre and leaves faster than it came.
    readonly property int motionMs: open ? CortetsuDesign.motionPopoverMs : CortetsuDesign.motionPopoverExitMs
    Behavior on opacity {
        enabled: root.animate
        NumberAnimation { duration: root.motionMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut }
    }
    Behavior on scale {
        enabled: root.animate
        NumberAnimation { duration: root.motionMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut }
    }

    function close(): void {
        root.open = false;
        root.closed();
    }
}
