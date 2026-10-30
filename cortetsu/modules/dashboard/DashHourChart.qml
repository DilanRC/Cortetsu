pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../../components"
import "../../services"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The next hours as one ink line: each hour a point at its temperature, the
// figure above it and the hour below.
Item {
    id: chart
    property var hours: []
    readonly property var temps: hours.map(h => Number(h.tempC) || 0)
    readonly property real lo: temps.length ? Math.min(...temps) : 0
    readonly property real hi: temps.length ? Math.max(...temps) : 1
    readonly property real plotTop: 34
    readonly property real plotBottom: height - 30
    readonly property real step: hours.length > 1 ? width / hours.length : width

    function px(i: int): real { return step * (i + 0.5); }
    function py(i: int): real {
        const span = Math.max(1, hi - lo);
        return plotBottom - (temps[i] - lo) / span * (plotBottom - plotTop);
    }
    readonly property var points: temps.map((_, i) => Qt.point(px(i), py(i)))

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: chart.points.length > 1
        ShapePath {
            strokeWidth: 3
            strokeColor: Qt.alpha(CortetsuDesign.colorIndicator, 0.85)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: chart.points }
        }
    }

    Repeater {
        model: chart.hours
        Item {
            id: hour
            required property var modelData
            required property int index
            x: chart.px(index) - width / 2
            width: chart.step
            height: chart.height

            Rectangle {
                x: parent.width / 2 - 4
                y: chart.py(hour.index) - 4
                width: 8; height: 8; radius: height / 2
                color: CortetsuDesign.colorSumi
                border.width: 2
                border.color: CortetsuDesign.colorIndicator
            }
            DashInk {
                anchors.horizontalCenter: parent.horizontalCenter
                y: chart.py(hour.index) - height - 8
                text: CortetsuRegional.formatTemperature(hour.modelData.tempC)
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.Normal
            }
            CortetsuText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                text: `${String(hour.modelData.hour).padStart(2, "0")}:00`
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelMediumPx
            }
        }
    }
}
