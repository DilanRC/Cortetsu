import QtQuick
import QtQuick.Shapes
import "../theme"

// One horizontal brush stroke: a heavy start, a body that thins, and a
// lifted end. Used for the zone mark, progress and ranges. It draws to its
// own width, so a progress stroke is just a narrower one.
Shape {
    id: root
    property color ink: CortetsuDesign.colorIndicator
    property real inkAlpha: 0.9
    implicitHeight: 8
    preferredRendererType: Shape.CurveRenderer

    readonly property real w: Math.max(width, height)
    readonly property real h: height

    ShapePath {
        strokeWidth: -1
        fillColor: Qt.alpha(root.ink, root.inkAlpha)
        startX: 0; startY: root.h * 0.55
        PathQuad { controlX: root.h * 0.2; controlY: 0; x: root.h * 1.4; y: root.h * 0.08 }
        PathLine { x: root.w * 0.7; y: root.h * 0.22 }
        PathQuad { controlX: root.w - root.h * 0.2; controlY: root.h * 0.3; x: root.w; y: root.h * 0.62 }
        PathQuad { controlX: root.w - root.h * 0.5; controlY: root.h * 0.82; x: root.w * 0.7; y: root.h * 0.78 }
        PathLine { x: root.h * 1.4; y: root.h * 0.98 }
        PathQuad { controlX: root.h * 0.15; controlY: root.h; x: 0; y: root.h * 0.55 }
    }
}
