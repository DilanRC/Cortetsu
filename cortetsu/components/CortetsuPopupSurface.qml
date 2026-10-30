import QtQuick
import QtQuick.Shapes
import "../theme"

// Every popout sits on the ink material of the dashboard: a sumi ground, a
// faint wash of the wallpaper colour from the top corner and paper grain.
// The wash and grain are the first children, so the popout's own content
// always paints above them.
CortetsuSurface {
    id: root

    property color popupColor: Qt.alpha(CortetsuDesign.colorSumi, 0.95)
    property real popupRadius: CortetsuDesign.radiusLarge
    // Popouts are small; a lighter wash than the dashboard keeps rows legible.
    property real washAlpha: 0.22

    radiusValue: root.popupRadius
    baseColor: root.popupColor
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.08)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * 0.08; centerY: 0
                focalX: centerX; focalY: centerY
                centerRadius: Math.max(root.width, root.height) * 0.8
                GradientStop { position: 0; color: Qt.alpha(CortetsuDesign.colorPrimary, root.washAlpha) }
                GradientStop { position: 0.5; color: Qt.alpha(CortetsuDesign.colorPrimary, root.washAlpha * 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.radius }
        }
    }

    CortetsuGrain {
        anchors.fill: parent
        radius: root.radius
        strength: 0.09
    }
}
