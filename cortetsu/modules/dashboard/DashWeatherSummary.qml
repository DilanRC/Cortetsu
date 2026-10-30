pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The weather as a margin note: the temperature in ink, then the words.
DashNote {
    mark: "天"
    label: qsTr("TIEMPO")

    CortetsuText {
        visible: !Weather.cc
        Layout.fillWidth: true
        text: qsTr("Tiempo no disponible")
        color: CortetsuDesign.colorOnSurfaceVariant
        wrapMode: Text.Wrap
    }
    RowLayout {
        visible: !!Weather.cc
        spacing: CortetsuDesign.spacingStandard
        DashInk { text: Weather.temp; textSize: CortetsuTypography.inkLinePx }
        CortetsuText { text: Weather.icon; textSize: CortetsuTypography.iconMediumPx; color: CortetsuDesign.colorIndicator }
    }
    CortetsuText {
        visible: !!Weather.cc
        Layout.fillWidth: true
        text: [Weather.description, Weather.city].filter(s => !!s).join(" · ")
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
        elide: Text.ElideRight
    }
}
