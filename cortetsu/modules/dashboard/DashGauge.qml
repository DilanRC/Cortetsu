pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A gauge as an ensō with its figure in ink at the centre.
Item {
    id: gauge
    property string label
    property string mark
    property real value
    property string detail
    property real size: 150
    implicitWidth: size
    implicitHeight: size + caption.implicitHeight + CortetsuDesign.spacingCompact

    CortetsuEnso {
        id: enso
        width: gauge.size
        height: gauge.size
        value: gauge.value
        ink: gauge.value > 0.85 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
    }
    Row {
        anchors.centerIn: enso
        DashInk { text: Math.round(enso.shown * 100); textSize: gauge.size * 0.3 }
        CortetsuText { anchors.baseline: parent.children[0].baseline; text: "%"; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
    }
    DashNote {
        id: caption
        anchors.top: enso.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        anchors.horizontalCenter: enso.horizontalCenter
        mark: gauge.mark
        label: gauge.label
        CortetsuText {
            text: gauge.detail
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.bodySmallPx
        }
    }
}
