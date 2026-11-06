import QtQuick
import ".."
import "../../theme"
import "../../services"
import "../CortetsuOverlayPolicy.js" as OverlayPolicy

Item {
    id: root

    required property var screen
    required property var screenState
    required property bool sidebarOrSessionVisible
    readonly property var monitor: Brightness.getMonitorForScreen(screen)
    property real offsetScale: screenState?.osd || compactVisible ? 0 : 1
    property real sidebarOffset: sidebarOrSessionVisible ? CortetsuDesign.spacingStandard : 0
    property real volume: CortetsuAudio.volume
    property bool muted: CortetsuAudio.muted
    readonly property bool volumeAvailable: !!CortetsuAudio.sink?.ready && !!CortetsuAudio.sink?.audio
    property real brightness: monitor?.supported ? monitor.brightness : -1
    property bool compactVisible: false
    property string compactKind: "volume"
    readonly property bool fullVisible: !!screenState?.osd
    // Interactions.qml controls hover state through the wrapper instance.
    // Expose the child state instead of assigning an undeclared property.
    property alias hovered: content.hovered

    function show(): void {
        if (!screenState)
            return;
        compactTimer.stop();
        compactVisible = false;
        OverlayPolicy.open(CortetsuShellState.allStates(), screenState, "osd");
        hideTimer.restart();
    }

    function showMini(kind: string): void {
        if (!screenState || screenState.osd
                || screenState.cortetsuState?.fullscreenTransitionProgress >= 1)
            return;
        compactKind = kind;
        compactVisible = true;
        compactTimer.restart();
    }

    visible: offsetScale < 1
    anchors.rightMargin:
        (-implicitWidth - CortetsuDesign.spacingStandard - sidebarOffset) * offsetScale
    implicitWidth: fullVisible ? content.implicitWidth : mini.implicitWidth
    implicitHeight: fullVisible ? content.implicitHeight : mini.implicitHeight
    opacity: 1 - offsetScale
    // design-lint: allow motion-scale-from-zero: 0.98 to 1, slides in with the fade
    scale: 1 - 0.015 * offsetScale
    transformOrigin: Item.Right

    Connections {
        target: CortetsuAudio
        function onVolumeChanged(): void {
            root.volume = CortetsuAudio.volume;
            if (CortetsuShellState.forActive() === root.screenState)
                root.showMini("volume");
        }
        function onMutedChanged(): void {
            root.muted = CortetsuAudio.muted;
            if (CortetsuShellState.forActive() === root.screenState)
                root.showMini("volume");
        }
    }

    Connections {
        target: monitor
        function onBrightnessChanged(): void {
            root.brightness = monitor?.supported ? monitor.brightness : -1;
            root.showMini("brightness");
        }
    }

    Connections {
        target: root.screenState
        function onOsdChanged(): void {
            if (root.screenState?.osd) {
                compactTimer.stop();
                root.compactVisible = false;
                hideTimer.restart();
            } else {
                hideTimer.stop();
            }
        }
    }

    Behavior on offsetScale {
        NumberAnimation {
            duration: screenState?.osd
                ? CortetsuDesign.motionStandardMs
                : CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: {
            if (CortetsuShellState.screenshotActive) {
                restart();
                return;
            }
            if (root.screenState && !content.hovered)
                root.screenState.osd = false;
            else
                restart();
        }
    }

    Timer {
        id: compactTimer
        interval: 1300
        onTriggered: root.compactVisible = false
    }

    Content {
        id: content
        visible: root.fullVisible
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        monitor: root.monitor
        screenState: root.screenState
        screen: root.screen
        volume: root.volume
        muted: root.muted
        brightness: root.brightness
    }

    MiniSlider {
        id: mini
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        visible: root.compactVisible && !root.fullVisible
        kind: root.compactKind
        value: root.compactKind === "volume" ? root.volume : root.brightness
        maximum: root.compactKind === "volume" ? CortetsuConfig.maxVolume : 1
        available: root.compactKind === "volume" ? root.volumeAvailable : root.brightness >= 0
        muted: root.muted
    }
}
