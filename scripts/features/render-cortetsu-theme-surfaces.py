#!/usr/bin/env python3
"""Render the shared surfaces of the shell in Ink, Washi and Kurogane.

The same real components, data and size in each theme: a Bottom Hub
segment, an audio popout, a notification, the compact OSD and a panel of
the material the Dashboard, launcher and Hardware Center sit on. The
services are the Settings harness doubles, so nothing touches the host.

    render-cortetsu-theme-surfaces.py --out DIR
"""
import argparse
import tempfile
from pathlib import Path

from settings_harness import build_tree, run

SHELL = r"""import QtQuick
import QtQuick.Layouts
import Quickshell
import "modules"
import "modules/bar/popouts"
import "modules/notifications"
import "modules/osd" as Osd
import "components"
import "services"
import "theme"
import "modules/CortetsuTypography.js" as CortetsuTypography

ShellRoot {
    id: root
    readonly property string out: Quickshell.env("CORTETSU_RENDER_DIR")
    readonly property string theme: Quickshell.env("THEME_ID")
    // The shell always holds these; here nothing else would create them.
    readonly property var palette: CortetsuColours
    readonly property bool ready: CortetsuConfig.loaded && CortetsuThemes.reconciled
        && CortetsuDesign.materialStyle === ({ ink: 0, washi: 1, kurogane: 2 })[theme]

    QtObject { id: screenDouble; property bool settings: false }
    QtObject {
        id: notice
        property bool closed: false
        property int urgency: 1
        property string summary: "Copia terminada"
        property string appName: "Archivos"
        property string timeStr: "12:30"
        property string image: ""
        property string body: "Se guardaron 24 fotos en Imágenes/Viaje."
        property var actions: []
        property bool interactionActive: false
        function close() {}
        function lock(item) {}
        function unlock(item) {}
    }

    Window {
        id: window
        width: 1180
        height: 560
        visible: true
        color: CortetsuDesign.colorSumi

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: CortetsuDesign.colorSumi }
                GradientStop { position: 1; color: Qt.tint(CortetsuDesign.colorSumi, Qt.alpha(CortetsuDesign.colorPrimary, 0.3)) }
            }
        }

        // The material the Dashboard, launcher and Hardware Center use.
        CortetsuInkPanel {
            x: 24; y: 24; width: 420; height: 300
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12
                CortetsuText {
                    text: CortetsuDesign.labelCaps ? "PANEL" : "Panel"
                    textSize: CortetsuTypography.titleMediumPx
                    font.family: CortetsuDesign.fontHeading
                    font.weight: CortetsuDesign.headingWeight
                    font.letterSpacing: CortetsuDesign.labelTracking
                }
                CortetsuText { text: "Dashboard, lanzador y Hardware"; color: CortetsuDesign.colorOnSurfaceVariant }
                RowLayout {
                    spacing: 8
                    CortetsuButton { label: "Aplicar"; icon: "check"; active: true }
                    CortetsuButton { label: "Cancelar"; icon: "close" }
                }
                CortetsuSlider { Layout.fillWidth: true; value: 0.62; accessibleName: "Brillo" }
                RowLayout {
                    CortetsuText { Layout.fillWidth: true; text: "Modo de juego" }
                    CortetsuToggle { checked: true }
                }
            }
        }

        CortetsuAudioPopup {
            x: 468; y: 24; width: 340
            popouts: QtObject { property bool hasCurrent: true; function close() {} }
        }

        Notification {
            x: 832; y: 24; width: 324
            modelData: notice
            props: QtObject { property bool expanded: false }
            expanded: false
            screenState: screenDouble
        }

        Osd.MiniSlider {
            x: 832; y: 220
            kind: "volume"; value: 0.62; maximum: 1; available: true; muted: false
        }

        // A Bottom Hub segment on its island.
        CortetsuStatusSegment {
            x: 24; y: 360; width: 520
            notificationCount: 3
            volumeIcon: "volume_up"; volumeMuted: false
            networkIcon: "wifi"; networkTooltip: "Wi-Fi"; networkActive: true
            bluetoothIcon: "bluetooth"; bluetoothActive: true
            batteryIcon: "battery_full"; batteryCritical: false; batteryTooltip: "Batería"
            audioVisible: true; networkVisible: true; bluetoothVisible: true; batteryVisible: true
            statusPopoutsEnabled: false; sidebarActive: false; recordingActive: false
            dndActive: false; idleInhibited: false
            now: new Date(2026, 0, 1, 13, 5)
            sessionActive: false
        }
    }

    Timer {
        interval: 1200; running: root.ready
        onTriggered: window.contentItem.grabToImage(result => {
            result.saveToFile(`${root.out}/surfaces-${root.theme}.png`);
            console.log("SETTINGS_RUNTIME_PASS 1");
            Qt.quit();
        })
    }
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cortetsu-surfaces-") as temporary:
        folder = Path(temporary)
        build_tree(folder)
        (folder / "surfaces.qml").write_text(SHELL, encoding="utf-8")
        for theme in ("ink", "washi", "kurogane"):
            output, _ = run(folder, "surfaces.qml", "surfaces", label=theme,
                            preferences={"schema": 1, "themeId": theme},
                            scheme={"schema": 2, "themeId": theme, "name": theme, "flavour": "default",
                                    "variant": "tonal-spot", "origin": "theme", "colours": {}},
                            env={"CORTETSU_RENDER_DIR": str(args.out.resolve()), "THEME_ID": theme})
            assert "SETTINGS_RUNTIME_PASS" in output, output
            print("RENDERED", theme, flush=True)


if __name__ == "__main__":
    main()
