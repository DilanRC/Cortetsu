import QtQuick
import "../theme"

// One floating BottomHub island: full pill, translucent scheme surface and a
// faint inner edge so it reads on light and busy wallpapers alike. Colours
// come from the wallpaper scheme through CortetsuDesign.
Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    z: -1
    radius: Math.min(height / 2, CortetsuDesign.radiusSurface)
    color: Qt.alpha(CortetsuDesign.colorSumi, 0.82)
    border.width: 1
    border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.08)
}
