import QtQuick
import QtQuick.Shapes

// Chamfered rectangle shared by the stage, the tiles and their masks.
Shape {
    id: root

    property real chamfer: 12
    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: 0
    readonly property real cut: Math.min(chamfer, width / 2, height / 2)

    ShapePath {
        fillColor: root.fillColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
        startX: root.cut; startY: 0
        PathLine { x: root.width - root.cut; y: 0 }
        PathLine { x: root.width; y: root.cut }
        PathLine { x: root.width; y: root.height - root.cut }
        PathLine { x: root.width - root.cut; y: root.height }
        PathLine { x: root.cut; y: root.height }
        PathLine { x: 0; y: root.height - root.cut }
        PathLine { x: 0; y: root.cut }
        PathLine { x: root.cut; y: 0 }
    }
}
