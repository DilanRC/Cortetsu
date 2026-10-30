import QtQuick
import QtQuick.Shapes
import "../theme"

// The ink material: sumi ground, a wash of the wallpaper colour bleeding
// from one corner, paper grain and a hairline edge. Every surface in the ink
// language sits on this instead of a flat translucent rectangle.
Item {
    id: root
    property real radius: CortetsuDesign.radiusSurface
    property color ground: CortetsuDesign.colorSumi
    property real groundAlpha: 0.95
    property color wash: CortetsuDesign.colorPrimary
    property real washAlpha: 0.34
    // Where the wash bleeds from, in fractions of the panel.
    property real washX: 0.05
    property real washY: 0.0
    property real grain: 0.11

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(root.ground, root.groundAlpha)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * root.washX; centerY: root.height * root.washY
                focalX: centerX; focalY: centerY
                centerRadius: Math.max(root.width, root.height) * 0.75
                GradientStop { position: 0; color: Qt.alpha(root.wash, root.washAlpha) }
                GradientStop { position: 0.5; color: Qt.alpha(root.wash, root.washAlpha * 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.radius }
        }
    }

    CortetsuGrain {
        anchors.fill: parent
        radius: root.radius
        strength: root.grain
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.07)
    }
}
