import QtQuick
import QtQuick.Effects

// Paper grain over a rounded area. The texture tiles; the mask keeps it
// inside the corners. It is static, so the layer renders once.
Item {
    id: root
    property real radius: 0
    property real strength: 0.07
    // Paper grain by default; Kurogane tiles brushed steel instead.
    property url texture: Qt.resolvedUrl("../assets/texture/grain.png")

    Image {
        id: grain
        anchors.fill: parent
        // Relative to this file, so it loads without Quickshell (qmltestrunner).
        source: root.texture
        fillMode: Image.Tile
        visible: false
        smooth: false
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: grain
        maskEnabled: true
        maskSource: mask
        opacity: root.strength
    }
}
