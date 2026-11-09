import QtQuick
import QtQuick.Shapes
import "../theme"
import "../modules"

// The material every large surface sits on: the dashboard, the session,
// Settings, Quick Settings and every popout (through CortetsuPopupSurface).
// Its strengths are the material.* tokens and its identity is
// CortetsuDesign.materialStyle, so a theme changes them all at once:
//
//   0 Ink       sumi ground, a wash of the accent bleeding from one corner,
//               paper grain and a hairline edge.
//   1 Washi     warm paper lit from above, visible fibres, a soft shadow
//               under it and almost no edge: the sheet is told apart from
//               the desk by light, not by a line.
//   2 Kurogane  matte steel darkening downwards, brushed streaks, a crisp
//               outline with a bevel highlight and corner marks.
//
// Every layer is static: no animation and no shader runs while it shows.
Item {
    id: root
    property real radius: CortetsuDesign.radiusSurface
    property int style: CortetsuDesign.materialStyle
    property color ground: CortetsuDesign.colorSumi
    // "Superficies transparentes" thins the ground by the material's
    // transparency factor, the same one CortetsuSurface uses. The wash
    // thins with it: the wallpaper now tints the ink itself, and a full wash
    // on top lifted a light wallpaper's ground past AA for secondary text.
    readonly property real transparencyFactor: CortetsuConfig.transparencyEnabled ? CortetsuDesign.materialTransparencyFactor : 1
    property real groundAlpha: CortetsuDesign.materialGroundAlpha * transparencyFactor
    property color wash: CortetsuDesign.colorPrimary
    property real washAlpha: CortetsuDesign.materialWashAlpha
    // Where the wash bleeds from, in fractions of the panel.
    property real washX: 0.05
    property real washY: 0.0
    property real grain: CortetsuDesign.materialGrain
    property bool hairline: true
    property color edge: CortetsuDesign.colorWashi
    property color accent: CortetsuDesign.colorIndicator
    property real shadowAlpha: CortetsuDesign.materialShadowAlpha
    // Corner marks belong to panels, not to chips and small cards.
    property bool marks: width >= 240 && height >= 120

    readonly property bool ink: style === 0
    readonly property bool washi: style === 1
    readonly property bool steel: style === 2

    // Washi: a shadow falling below the sheet, wider and fainter outwards.
    Repeater {
        model: root.washi && root.shadowAlpha > 0 ? 3 : 0
        Rectangle {
            required property int index
            readonly property real spread: 2 + index * 4
            x: -spread / 2
            y: -spread / 2 + 2 + index * 2
            width: root.width + spread
            height: root.height + spread
            radius: root.radius + spread / 2
            color: Qt.alpha(CortetsuDesign.colorOnSurface, root.shadowAlpha * (0.5 - index * 0.14) * root.transparencyFactor)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(root.ground, root.groundAlpha)
        visible: root.ink
    }

    // Paper and steel are lit: the ground is a vertical gradient. Paper
    // brightens at the top edge; steel darkens towards its foot.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.ink
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(root.washi ? Qt.lighter(root.ground, 1.035) : Qt.lighter(root.ground, 1.22), root.groundAlpha)
            }
            GradientStop {
                position: root.washi ? 0.35 : 0.5
                color: Qt.alpha(root.ground, root.groundAlpha)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(root.washi ? Qt.darker(root.ground, 1.025) : Qt.darker(root.ground, 1.18), root.groundAlpha)
            }
        }
    }

    Shape {
        anchors.fill: parent
        visible: root.washAlpha > 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * root.washX; centerY: root.height * root.washY
                focalX: centerX; focalY: centerY
                centerRadius: Math.max(root.width, root.height) * (root.washi ? 0.6 : 0.75)
                GradientStop { position: 0; color: Qt.alpha(root.wash, root.washAlpha * root.transparencyFactor) }
                GradientStop { position: 0.5; color: Qt.alpha(root.wash, root.washAlpha * root.transparencyFactor * 0.35) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.radius }
        }
    }

    CortetsuGrain {
        anchors.fill: parent
        visible: strength > 0
        radius: root.radius
        strength: root.steel ? 0.5 * root.transparencyFactor : root.grain
        texture: root.steel ? Qt.resolvedUrl("../assets/texture/brushed.png") : Qt.resolvedUrl("../assets/texture/grain.png")
    }

    // Ink and Washi: one hairline. On paper it is barely there.
    Rectangle {
        anchors.fill: parent
        visible: root.hairline && !root.steel
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(root.edge, CortetsuDesign.materialHairlineAlpha)
    }

    // Washi: the top edge of the sheet catches the light.
    Rectangle {
        visible: root.washi
        x: root.radius
        width: root.width - root.radius * 2
        y: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.7 * root.transparencyFactor)
    }

    // Kurogane: a precise outline, a bevel highlight just inside it, and
    // short marks at the corners in the accent.
    Rectangle {
        anchors.fill: parent
        visible: root.steel && root.hairline
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.95)
    }

    Rectangle {
        visible: root.steel
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
    }

    Rectangle {
        visible: root.steel
        x: root.radius + 1
        width: root.width - root.radius * 2 - 2
        y: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.14)
    }

    Repeater {
        model: root.steel && root.marks ? 4 : 0
        Item {
            id: corner
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            readonly property real inset: Math.max(5, root.radius * 0.6)
            width: 12
            height: 12
            x: atRight ? root.width - width - inset : inset
            y: atBottom ? root.height - height - inset : inset

            Rectangle {
                width: parent.width
                height: 1
                y: corner.atBottom ? parent.height - 1 : 0
                color: Qt.alpha(root.accent, 0.7)
            }
            Rectangle {
                width: 1
                height: parent.height
                x: corner.atRight ? parent.width - 1 : 0
                color: Qt.alpha(root.accent, 0.7)
            }
        }
    }
}
