import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import ".."
import "../../services"
import "../desktop"

Variants {
    model: CortetsuScreens.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData
        // Orbital ownership handshake: this surface is the static cover. It
        // confirms each frame where the cover is opaque ("covered") or lifted
        // ("revealed") so the supervisor never leaves the monitor uncovered.
        readonly property var orbital: Orbital.output(modelData?.name ?? "")
        readonly property bool animated: Orbital.available && orbital.reveal === true
        readonly property bool participating: (orbital.generation ?? 0) > 0 && (orbital.state !== "stopped" || orbital.covered !== true)
        property string acknowledged: ""
        property string pendingKey: ""
        property int pendingFrames: 0

        screen: modelData
        WlrLayershell.namespace: "cortetsu-background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        // Bottom keeps the static cover and widgets above an Orbital renderer,
        // which maps on the background layer of the same monitor.
        WlrLayershell.layer: WlrLayer.Bottom
        // The opaque ground under the image and the Orbital cover is the same
        // in every theme: a light theme must not flash its paper before the
        // first frame of the wallpaper.
        // design-lint: allow color-untinted-neutral: theme-independent ground, seen only before the wallpaper's first frame
        color: (CortetsuConfig.wallpaperEnabled || participating) && !animated ? "black" : "transparent" // design-lint: allow token-literal-color: theme-independent ground
        surfaceFormat.opaque: false
        onOrbitalChanged: {
            const key = orbital.generation + ":" + animated + ":" + orbital.state;
            if (acknowledged !== key && contentItem.Window.window) contentItem.Window.window.update();
        }
        function acknowledgeFrame(): void {
            if (!Orbital.available || !(orbital.generation > 0)) return;
            const key = orbital.generation + ":" + animated + ":" + orbital.state;
            if (acknowledged === key) return;
            // The first swap after a change may still carry the frame rendered
            // before it; the second one is certain to show the new state.
            if (pendingKey !== key) { pendingKey = key; pendingFrames = 0; }
            if (++pendingFrames < 2) { contentItem.Window.window?.update(); return; }
            acknowledged = key;
            Orbital.send({op: animated ? "revealed" : "covered", monitor: modelData.name, generation: orbital.generation});
        }
        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped(): void { win.acknowledgeFrame(); }
        }

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ShellState.ComponentRef {
            screen: win.screen
            slot: "background"
            component: win
        }

        Item {
            id: behindWidgets
            anchors.fill: parent

            Loader {
                id: wallpaper
                anchors.fill: parent
                asynchronous: true
                active: CortetsuConfig.wallpaperEnabled || win.participating
                visible: !win.animated
                sourceComponent: Wallpaper {}
            }

            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: wallpaper
            }
        }

        // Desktop widgets (clock, calendar, weather, system...), placed in
        // the editor. The 2.x desktop clock became the first of them.
        DesktopWidgetLayer {
            anchors.fill: parent
            screen: win.modelData
        }
    }
}
