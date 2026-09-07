import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../../services"

Item {
    id: root

    required property var screen
    required property var screenState
    required property bool sidebarOrSessionVisible
    readonly property var monitor: Brightness.getMonitorForScreen(screen)
    property real offsetScale: screenState.osd ? 0 : 1
    property real sidebarOffset: sidebarOrSessionVisible ? CortetsuDesign.spacingStandard : 0
    property real volume: CortetsuAudio.volume
    property bool muted: CortetsuAudio.muted
    property real brightness: monitor?.supported ? monitor.brightness : -1
    // Interactions.qml controls hover state through the wrapper instance.
    // Expose the child state instead of assigning an undeclared property.
    property alias hovered: content.hovered

    function show(): void {
        screenState.osd = true;
        hideTimer.restart();
    }

    visible: offsetScale < 1
    anchors.rightMargin:
        (-implicitWidth - CortetsuDesign.spacingStandard - sidebarOffset) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale
    scale: 1 - 0.015 * offsetScale
    transformOrigin: Item.Right

    Connections {
        target: CortetsuAudio
        function onVolumeChanged(): void {
            root.volume = CortetsuAudio.volume;
            root.show();
        }
        function onMutedChanged(): void {
            root.muted = CortetsuAudio.muted;
            root.show();
        }
    }

    Connections {
        target: monitor
        function onBrightnessChanged(): void {
            root.brightness = monitor?.supported ? monitor.brightness : -1;
            root.show();
        }
    }

    Behavior on offsetScale {
        NumberAnimation {
            duration: screenState.osd
                ? CortetsuDesign.motionStandardMs
                : CortetsuDesign.motionFastMs
            easing.type: screenState.osd ? Easing.OutCubic : Easing.InCubic
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: {
            if (!content.hovered)
                root.screenState.osd = false;
            else
                restart();
        }
    }

    Content {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        monitor: root.monitor
        screenState: root.screenState
        volume: root.volume
        muted: root.muted
        brightness: root.brightness
    }
}
