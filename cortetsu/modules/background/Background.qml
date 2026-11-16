import QtQuick
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

        screen: modelData
        WlrLayershell.namespace: "cortetsu-background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: CortetsuConfig.wallpaperEnabled ? WlrLayer.Background : WlrLayer.Bottom
        color: CortetsuConfig.wallpaperEnabled ? "black" : "transparent"
        surfaceFormat.opaque: false

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
                active: CortetsuConfig.wallpaperEnabled
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
