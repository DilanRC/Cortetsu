import QtQuick
import "../theme"

// A grouping inside an ink panel. The ink stays visible through it: a faint
// washi veil and the same hairline as the panel edge, never a flat block of
// container colour.
Rectangle {
    radius: CortetsuDesign.radiusMedium
    color: Qt.alpha(CortetsuDesign.colorWashi, CortetsuDesign.materialHairlineAlpha * 0.35)
    border.width: 1
    border.color: Qt.alpha(CortetsuDesign.colorWashi, CortetsuDesign.materialHairlineAlpha)
}
