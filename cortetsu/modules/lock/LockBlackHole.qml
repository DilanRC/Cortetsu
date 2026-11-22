import QtQuick
import "../../components"
import "../../theme"

// What the mark sits in (Nebula's BlackHole, redrawn): a halo of the accent
// and dots on three rings turning at their own speed, inner ones faster.
// While music plays the rings turn faster. Each ring is one rotating item,
// so the motion costs a transform, not a repaint.
Item {
    id: root

    property bool playing: false
    property color tone: CortetsuDesign.colorPrimary
    readonly property real r: width / 2

    function rand(seed: real): real {
        const x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453;
        return x - Math.floor(x);
    }

    CortetsuInkPanel {
        anchors.centerIn: parent
        width: root.width * 3.2
        height: width
        radius: width / 2
        groundAlpha: 0
        grain: 0
        hairline: false
        marks: false
        wash: root.tone
        washAlpha: 0.32
        washX: 0.5
        washY: 0.5
        washReach: 0.5
    }

    Repeater {
        model: [[1.55, 26, 34000], [2.2, 30, 56000], [2.95, 34, 90000]]
        delegate: Item {
            id: ring
            required property var modelData
            required property int index
            anchors.centerIn: parent
            width: root.width * modelData[0]
            height: width
            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: ring.modelData[2] / (root.playing ? 3 : 1)
                loops: Animation.Infinite
                running: root.visible && !CortetsuDesign.reducedMotion
            }
            Repeater {
                model: ring.modelData[1]
                delegate: Rectangle {
                    required property int index
                    readonly property real a: root.rand(index + ring.index * 100 + 50) * Math.PI * 2
                    readonly property real spread: 0.88 + root.rand(index + ring.index * 100 + 7) * 0.24
                    width: 2 + root.rand(index + ring.index * 31) * 3
                    height: width
                    radius: width / 2
                    x: ring.width / 2 + Math.cos(a) * ring.width / 2 * spread - width / 2
                    y: ring.height / 2 + Math.sin(a) * ring.height / 2 * spread * 0.94 - height / 2
                    color: Qt.alpha(Qt.lighter(root.tone, 1.6), 0.45 + root.rand(index * 3 + ring.index) * 0.5)
                }
            }
        }
    }
}
