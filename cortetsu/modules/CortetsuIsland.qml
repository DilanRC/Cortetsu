import QtQuick
import "."
import "../theme"
import "../theme/CortetsuDesignDefaults.js" as CortetsuDefaults

// One floating BottomHub island: full pill, translucent scheme surface and a
// faint inner edge so it reads on light and busy wallpapers alike. Colours
// come from the wallpaper scheme through CortetsuDesign.
Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    z: -1
    // Preserve the current Ink island alpha, while letting theme ground
    // opacity and the global transparency setting affect the other profiles.
    property real transparencyFactor: CortetsuConfig.transparencyEnabled
        ? CortetsuDesign.materialTransparencyFactor
        : 1
    readonly property real materialAlpha:
        0.82 * CortetsuDesign.materialGroundAlpha / CortetsuDefaults.materialGroundAlpha * transparencyFactor
    radius: Math.min(height / 2, CortetsuDesign.radiusSurface)
    color: Qt.alpha(CortetsuDesign.colorSumi, materialAlpha)
    border.width: CortetsuConfig.borderThickness
    border.color: Qt.alpha(CortetsuDesign.colorWashi,
        0.08 * CortetsuDesign.materialHairlineAlpha / CortetsuDefaults.materialHairlineAlpha)
}
