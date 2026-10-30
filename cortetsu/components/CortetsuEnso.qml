import QtQuick
import QtQuick.Shapes
import "../theme"

// An ensō: a circle drawn in one brush stroke, as long as `value` (0..1).
// Three passes with slightly different widths, radii and lengths give the
// stroke its uneven edge; a thin dry tail runs a little past the wet ink.
Item {
    id: root
    property real value: 0
    property color ink: CortetsuDesign.colorIndicator
    property real stroke: Math.max(6, width * 0.07)
    readonly property real shown: Math.max(0, Math.min(1, animated))
    property real animated: value
    Behavior on animated { NumberAnimation { duration: CortetsuDesign.motionDeliberateMs; easing.type: Easing.OutCubic } }

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real r: Math.min(width, height) / 2 - stroke
    // A brush starts at the lower left and sweeps clockwise.
    readonly property real start: 112

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The paper circle the stroke will fill.
        ShapePath {
            strokeWidth: 1.5
            strokeColor: Qt.alpha(CortetsuDesign.colorWashi, 0.08)
            fillColor: "transparent"
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r; radiusY: root.r; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: 1.2
            strokeColor: Qt.alpha(root.ink, 0.35)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r + root.stroke * 0.3; radiusY: root.r + root.stroke * 0.3; startAngle: root.start - 4; sweepAngle: 360 * Math.min(1, root.shown * 1.04 + 0.01) }
        }
        ShapePath {
            strokeWidth: root.stroke
            strokeColor: Qt.alpha(root.ink, 0.9)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r; radiusY: root.r; startAngle: root.start; sweepAngle: 360 * root.shown * 0.97 }
        }
        ShapePath {
            strokeWidth: root.stroke * 0.55
            strokeColor: Qt.alpha(root.ink, 0.55)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r - root.stroke * 0.35; radiusY: root.r - root.stroke * 0.35; startAngle: root.start + 3; sweepAngle: 360 * root.shown }
        }
        ShapePath {
            strokeWidth: root.stroke * 0.4
            strokeColor: Qt.alpha(root.ink, 0.4)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r + root.stroke * 0.3; radiusY: root.r + root.stroke * 0.3; startAngle: root.start - 2; sweepAngle: 360 * root.shown * 0.9 }
        }
    }
}
