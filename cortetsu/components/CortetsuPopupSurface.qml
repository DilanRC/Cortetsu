import QtQuick
import "../theme"

// Every popout sits on the ink material (CortetsuInkPanel), with the popup
// strengths of ui.toml's [material]. The panel is the first child, so the
// popout's own content always paints above it. The surface itself only
// keeps the shape and the hairline edge, so focus and hover outlines of
// CortetsuSurface still work.
CortetsuSurface {
    id: root

    property color popupColor: "transparent"
    property real popupRadius: CortetsuDesign.radiusLarge

    radiusValue: root.popupRadius
    baseColor: root.popupColor
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorWashi, CortetsuDesign.materialHairlineAlpha)

    CortetsuInkPanel {
        anchors.fill: parent
        z: -1
        radius: root.radius
        washX: 0.08
        washAlpha: CortetsuDesign.materialPopupWashAlpha
        grain: CortetsuDesign.materialPopupGrain
        hairline: false
    }
}
