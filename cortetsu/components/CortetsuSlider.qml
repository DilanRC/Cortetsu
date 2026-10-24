import QtQuick
import "../theme"

Item {
    id: root

    // Avoid an arbitrary slider becoming the keyboard owner when a panel
    // loads. Mouse and Tab navigation still call into this control normally.
    focus: false
    enabled: !disabled
    activeFocusOnTab: true

    // `value` belongs to the caller and is never assigned here, so a binding
    // on it survives a drag and keeps following the backend.
    property real value: 0
    property real dragValue: 0
    readonly property bool dragging: mouse.pressed
    readonly property real shownValue: dragging ? dragValue : value
    property real from: 0
    property real to: 1
    property bool disabled: false
    property real step: 0.05
    // What the slider sets ("Volumen"); read by screen readers with the value.
    property string accessibleName: ""
    // Spoken value; the percentage of the range unless the caller has a unit.
    property string accessibleValue: Math.round(root.progress * 100) + " %"
    signal moved(real value)

    implicitHeight: 30
    opacity: disabled ? 0.46 : 1

    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleValue
    Accessible.focusable: !disabled
    Accessible.focused: root.activeFocus
    Accessible.onIncreaseAction: if (!root.disabled) root.adjust(root.step)
    Accessible.onDecreaseAction: if (!root.disabled) root.adjust(-root.step)

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: mouse.containsMouse || root.activeFocus ? 5 : 4
        radius: height / 2
        color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.92)

        Behavior on height {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            width: track.width * root.progress
            height: parent.height
            radius: parent.radius
            color: CortetsuDesign.colorPrimary

            Behavior on width {
                enabled: !mouse.pressed
                NumberAnimation {
                    duration: CortetsuDesign.motionFastMs
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: handle
        width: handle.width + 10
        height: width
        radius: width / 2
        color: Qt.alpha(CortetsuDesign.colorPrimary, root.activeFocus ? 0.18 : mouse.containsMouse ? 0.1 : 0)

        Behavior on color {
            ColorAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: handle
        width: mouse.pressed || root.activeFocus ? 17 : mouse.containsMouse ? 16 : 14
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(root.width - width, root.progress * (root.width - width)))
        anchors.verticalCenter: parent.verticalCenter
        color: mouse.containsMouse || mouse.pressed || root.activeFocus
            ? CortetsuDesign.colorWashi
            : CortetsuDesign.colorPrimary
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorOutline, 0.72)

        Behavior on x {
            enabled: !mouse.pressed
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on width {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }

    readonly property real progress: root.to === root.from
        || !Number.isFinite(root.shownValue)
        || !Number.isFinite(root.from) || !Number.isFinite(root.to)
        ? 0
        : Math.max(0, Math.min(1, (root.shownValue - root.from) / (root.to - root.from)))

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: event => {
            root.forceActiveFocus();
            root.setFromPosition(event.x);
        }
        onPositionChanged: event => {
            if (pressed)
                root.setFromPosition(event.x);
        }
    }

    function setFromPosition(position: real): void {
        if (root.width <= 0 || !Number.isFinite(position)
                || !Number.isFinite(root.from) || !Number.isFinite(root.to))
            return;
        const next = root.from + Math.max(0, Math.min(1, position / root.width)) * (root.to - root.from);
        root.dragValue = next;
        root.moved(next);
    }

    function adjust(delta: real): void {
        if (!Number.isFinite(root.from) || !Number.isFinite(root.to) || !Number.isFinite(delta))
            return;
        const current = Number.isFinite(root.value) ? root.value : root.from;
        root.moved(Math.max(Math.min(root.from, root.to),
            Math.min(Math.max(root.from, root.to), current + delta)));
    }

    Keys.onLeftPressed: root.adjust(-root.step)
    Keys.onRightPressed: root.adjust(root.step)
    Keys.onDownPressed: root.adjust(-root.step)
    Keys.onUpPressed: root.adjust(root.step)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            root.adjust((event.key === Qt.Key_PageUp ? 1 : -1) * root.step * 5);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            root.moved(root.from);
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            root.moved(root.to);
            event.accepted = true;
        }
    }
}
