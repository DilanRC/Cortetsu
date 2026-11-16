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

// A gauge as an ensō with its figure in ink at the centre. Every gauge uses
// the same size and the same figure size, so a row of them reads as one set.
Item {
    id: gauge
    property string label
    property string mark
    property real value
    property string detail
    // Without a reading the ring stays empty and says so; a 0 % ring would
    // read as a real figure.
    property bool available: true
    readonly property real size: 150
    implicitWidth: size
    implicitHeight: size + caption.implicitHeight + CortetsuDesign.spacingCompact
    Accessible.role: Accessible.Indicator
    Accessible.name: gauge.label
    Accessible.description: gauge.available ? `${Math.round(gauge.value * 100)} % · ${gauge.detail}` : gauge.detail

    CortetsuEnso {
        id: enso
        anchors.horizontalCenter: parent.horizontalCenter
        width: gauge.size
        height: gauge.size
        value: gauge.available ? gauge.value : 0
        opacity: gauge.available ? 1 : 0.4
        ink: gauge.value > 0.85 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
    }
    CortetsuText {
        anchors.centerIn: enso
        visible: !gauge.available
        text: qsTr("Sin lectura")
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
    }
    Row {
        anchors.centerIn: enso
        visible: gauge.available
        DashInk { id: figure; text: Math.round(enso.shown * 100); textSize: CortetsuTypography.inkTitlePx }
        CortetsuText { anchors.baseline: figure.baseline; text: "%"; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
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
