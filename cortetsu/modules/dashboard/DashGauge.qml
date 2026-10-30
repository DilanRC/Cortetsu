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

Rectangle {
    id: gauge
    radius: CortetsuDesign.radiusLarge
    color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.55)
    border.width: 1
    border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.05)
    property string icon
    property string label
    property real value
    property string detail
    Layout.fillWidth: true
    Layout.preferredHeight: 250

    Item {
        id: ring
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: CortetsuDesign.spacingSpacious
        width: 140
        height: 140
        property real shown: Math.max(0, Math.min(1, gauge.value))
        Behavior on shown { NumberAnimation { duration: CortetsuDesign.motionStandardMs * 1.6; easing.type: Easing.OutCubic } }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 10; strokeColor: Qt.alpha(CortetsuDesign.colorOnSurface, 0.1); fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 70; centerY: 70; radiusX: 64; radiusY: 64; startAngle: 135; sweepAngle: 270 }
            }
            ShapePath {
                strokeWidth: 10; strokeColor: ring.shown > 0.85 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 70; centerY: 70; radiusX: 64; radiusY: 64; startAngle: 135; sweepAngle: 270 * ring.shown }
            }
        }
        Column {
            anchors.centerIn: parent
            CortetsuIcon { anchors.horizontalCenter: parent.horizontalCenter; text: gauge.icon; color: CortetsuDesign.colorOnSurfaceVariant }
            CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: `${Math.round(ring.shown * 100)}%`; textSize: CortetsuTypography.displayClockPx; font.weight: Font.DemiBold }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: ring.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        spacing: 2
        CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: gauge.label; font.weight: Font.DemiBold }
        CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: gauge.detail; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
    }
}
