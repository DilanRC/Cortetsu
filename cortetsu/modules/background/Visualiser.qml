import QtQuick
import Quickshell
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../../services"
import ".."

Item {
    id: root

    required property ShellScreen screen
    required property Item wallpaper

    readonly property bool hasFloatingWorkspace: {
        const monitor = CortetsuHypr.monitorFor(root.screen);
        return monitor?.activeWorkspace?.toplevels?.values?.every(t => t.lastIpcObject?.floating) ?? true;
    }
    readonly property bool shouldBeActive:
        CortetsuConfig.visualiserEnabled
        && (!CortetsuConfig.visualiserAutoHide || root.hasFloatingWorkspace)
    property real offset: root.shouldBeActive ? 0 : (root.screen?.height ?? 0) * 0.2

    opacity: root.shouldBeActive ? 1 : 0
    anchors.fill: parent

    Row {
        id: bars
        anchors.fill: parent
        anchors.margins: CortetsuConfig.borderThickness
        anchors.leftMargin: CortetsuConfig.borderThickness + 4 * CortetsuConfig.visualiserSpacing
        anchors.topMargin: root.offset
        anchors.bottomMargin: -root.offset
        spacing: Math.max(1, 2 * CortetsuConfig.visualiserSpacing)

        // The model is the bar count, not the sample list: a new sample
        // updates heights without recreating the bars.
        Repeater {
            model: CortetsuSpectrum.barCount

            Rectangle {
                required property int index
                readonly property real level: CortetsuSpectrum.values[index] ?? 0
                width: Math.max(1, (bars.width - bars.spacing * (CortetsuSpectrum.barCount - 1)) / Math.max(1, CortetsuSpectrum.barCount))
                height: Math.max(1, bars.height * level)
                anchors.bottom: parent.bottom
                radius: Math.max(0, 4 * CortetsuConfig.visualiserRounding)
                color: index % 2 ? CortetsuDesign.colorSecondary : CortetsuDesign.colorPrimary
                opacity: 0.7

                // Each bar is anchored on its own; nothing lays out from its
                // height, and scaling would squash its rounded ends.
                // design-lint: allow motion-layout-property: an anchored bar with no dependants
                Behavior on height { NumberAnimation { duration: CortetsuDesign.motionInstantMs } }
            }
        }
    }

    Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionStandardMs } }
    Behavior on offset { NumberAnimation { duration: CortetsuDesign.motionStandardMs } }
}
