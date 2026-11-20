import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
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
    // "volume" | "brightness" | "microphone" | "profile" | "media"
    property string compactKind: "volume"
    // power-profiles-daemon reports its first value after start-up; that
    // reading is not a change the user made and is not announced.
    property bool profileSettled: false
    // The microphone whose mute state has been seen settled. A mute change
    // that arrives with a new default source is that source's own state,
    // not something the user just did, and is not announced.
    property var settledSource: CortetsuAudio.source
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
        function onSourceChanged(): void {
            Qt.callLater(() => root.settledSource = CortetsuAudio.source);
        }
        function onSourceMutedChanged(): void {
            if (CortetsuAudio.source && root.settledSource === CortetsuAudio.source
                    && CortetsuShellState.forActive() === root.screenState)
                root.showMini("microphone");
        }
    }

    Connections {
        target: PowerProfiles
        function onProfileChanged(): void {
            if (root.profileSettled && CortetsuShellState.forActive() === root.screenState)
                root.showMini("profile");
        }
    }

    // Play and pause of the active player (media keys, a headset button).
    // A new track is the "Reproduciendo ahora" toast's to announce; a
    // player that just became the active one is not a change the user made.
    Connections {
        target: Players.active
        function onPlaybackStateChanged(): void {
            if (CortetsuShellState.forActive() === root.screenState
                    && [MprisPlaybackState.Playing, MprisPlaybackState.Paused].includes(Players.active?.playbackState))
                root.showMini("media");
        }
    }

    Timer {
        running: true
        interval: 3000
        onTriggered: root.profileSettled = true
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
        interval: CortetsuConfig.osdTimeoutMs
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
        interval: Math.max(500, CortetsuConfig.osdTimeoutMs - 200)
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
        value: root.compactKind === "volume" ? root.volume
            : root.compactKind === "microphone" ? CortetsuAudio.sourceVolume
            : root.compactKind === "profile" ? PowerProfiles.profile
            : root.compactKind === "media" ? (Players.active?.playbackState === MprisPlaybackState.Playing ? 1 : 0)
            : root.brightness
        maximum: root.compactKind === "brightness" ? 1 : CortetsuConfig.maxVolume
        available: root.compactKind === "volume" ? root.volumeAvailable
            : root.compactKind === "microphone" ? !!CortetsuAudio.source?.audio
            : root.compactKind === "profile" ? true
            : root.compactKind === "media" ? !!Players.active : root.brightness >= 0
        muted: root.compactKind === "microphone" ? CortetsuAudio.sourceMuted
            : root.compactKind === "profile" || root.compactKind === "media" ? false : root.muted
        // The output's own name, so a change of device is told apart.
        name: root.compactKind === "volume" ? (CortetsuAudio.sink?.description ?? "")
            : root.compactKind === "media" ? (Players.active?.trackTitle?.trim() ?? "") : ""
    }
}
