import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    focus: !disabled
    activeFocusOnTab: !disabled

    property real value: 0
    property real from: 0
    property real to: 1
    property bool disabled: false
    property real step: 0.05
    signal moved(real value)

    implicitHeight: 30
    opacity: disabled ? 0.46 : 1

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
        ? 0
        : Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from)))

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
        const next = root.from + Math.max(0, Math.min(1, position / root.width)) * (root.to - root.from);
        root.value = next;
        root.moved(next);
    }

    function adjust(delta: real): void {
        const next = Math.max(root.from, Math.min(root.to, root.value + delta));
        root.value = next;
        root.moved(next);
    }

    Keys.onLeftPressed: root.adjust(-root.step)
    Keys.onRightPressed: root.adjust(root.step)
    Keys.onDownPressed: root.adjust(-root.step)
    Keys.onUpPressed: root.adjust(root.step)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
            root.value = root.from;
            root.moved(root.value);
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            root.value = root.to;
            root.moved(root.value);
            event.accepted = true;
        }
    }
}
