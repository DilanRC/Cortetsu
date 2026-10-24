pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../components/containers"
import ".."

// Reserves the border on the edges whose panels are inset by it. The left
// edge reserves nothing since the top bar was retired (panels start at x 0).
// Every layer window costs a GL context, about 11 MiB and 4 threads each on
// the reference laptop, so a 0 px zone gets no window at all.
Variants {
    id: root
    required property ShellScreen screen
    property int thickness: CortetsuConfig.borderThickness

    model: root.thickness > 0 ? ["top", "right", "bottom"] : []

    StyledWindow {
        required property string modelData
        screen: root.screen
        name: "border-exclusion"
        anchors.top: modelData === "top"
        anchors.right: modelData === "right"
        anchors.bottom: modelData === "bottom"
        exclusiveZone: root.thickness
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
    }
}
