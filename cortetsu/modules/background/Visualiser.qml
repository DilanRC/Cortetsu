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

        Repeater {
            model: CortetsuSpectrum.values

            Rectangle {
                required property real modelData
                required property int index
                width: Math.max(1, (bars.width - (bars.spacing * (bars.children.length - 1))) / Math.max(1, CortetsuSpectrum.values.length))
                height: Math.max(1, bars.height * modelData)
                anchors.bottom: parent.bottom
                radius: Math.max(0, 4 * CortetsuConfig.visualiserRounding)
                color: index % 2 ? CortetsuDesign.colorSecondary : CortetsuDesign.colorPrimary
                opacity: 0.7

                Behavior on height { NumberAnimation { duration: 100 } }
            }
        }
    }

    Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionStandardMs } }
    Behavior on offset { NumberAnimation { duration: CortetsuDesign.motionStandardMs } }
}
