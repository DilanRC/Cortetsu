import QtQuick
import QtQuick.Shapes
import "../theme"
import "../modules"

// The ink material: sumi ground, a wash of the wallpaper colour bleeding
// from one corner, paper grain and a hairline edge. It is the one place the
// material is drawn: the dashboard, the session, Quick Settings and every
// popout (through CortetsuPopupSurface) sit on it, and its strengths are the
// material.* tokens of ui.toml, so a theme changes them all at once.
Item {
    id: root
    property real radius: CortetsuDesign.radiusSurface
    property color ground: CortetsuDesign.colorSumi
    // "Superficies transparentes" thins the ground with the same factor as
    // CortetsuSurface, so every ink surface lets the wallpaper through.
    property real groundAlpha: CortetsuDesign.materialGroundAlpha * (CortetsuConfig.transparencyEnabled ? 0.78 : 1)
    property color wash: CortetsuDesign.colorPrimary
    property real washAlpha: CortetsuDesign.materialWashAlpha
    // Where the wash bleeds from, in fractions of the panel.
    property real washX: 0.05
    property real washY: 0.0
    property real grain: CortetsuDesign.materialGrain
    property bool hairline: true

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
        visible: root.hairline
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, CortetsuDesign.materialHairlineAlpha)
    }
}
