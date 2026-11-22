import QtQuick
import "../../components"
import "../../theme"

// The sky in front of the blurred wallpaper (Nebula's LockStars and
// NebulaClouds, redrawn): a fixed star field, a few twinkling stars and
// clouds of the scheme's colours drifting slowly around the centre. Washes
// go through CortetsuInkPanel, the one painter of washes.
Item {
    id: root

    property real centerY: height * 0.4
    property real drift: 0
    readonly property var palette: [CortetsuDesign.colorPrimary, CortetsuDesign.colorIndicator,
        CortetsuDesign.colorSecondary, CortetsuDesign.colorPrimaryContainer, CortetsuDesign.colorVermillion]
    readonly property real unit: Math.max(0.7, height / 1080)

    function rand(seed: real): real {
        const x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453;
        return x - Math.floor(x);
    }

    NumberAnimation on drift {
        from: 0
        to: Math.PI * 2
        duration: 120000
        loops: Animation.Infinite
        running: root.visible && !CortetsuDesign.reducedMotion
    }

    Repeater {
        model: 14
        delegate: CortetsuInkPanel {
            required property int index
            readonly property real r: (90 + root.rand(index + 1) * 120) * root.unit
            readonly property real angle: root.rand(index + 40) * Math.PI * 2 + root.drift
            readonly property real dist: (40 + root.rand(index + 80) * 340) * root.unit
            width: r * 2
            height: r * 2
            radius: r
            x: root.width / 2 + Math.cos(angle) * dist - r
            y: root.centerY + Math.sin(angle) * dist * 0.7 - r
            groundAlpha: 0
            grain: 0
            hairline: false
            marks: false
            wash: root.palette[index % 5]
            washAlpha: 0.22
            washX: 0.5
            washY: 0.5
            washReach: 0.5
        }
    }

    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = "#e9e4ff";
            for (let i = 0; i < 260; ++i) {
                const big = root.rand(i + 1) > 0.9;
                ctx.globalAlpha = big ? 0.9 : 0.45;
                ctx.beginPath();
                ctx.arc(root.rand(i + 2) * width, root.rand(i + 3) * height, big ? 1.4 : 0.8, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    Repeater {
        model: 18
        delegate: Rectangle {
            required property int index
            x: root.rand(index * 7 + 101) * root.width
            y: root.rand(index * 7 + 102) * root.height
            width: 2
            height: 2
            radius: 1
            color: "#e9e4ff"
            opacity: 0
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.visible && !CortetsuDesign.reducedMotion
                PauseAnimation { duration: 400 + root.rand(index + 300) * 3200 }
                NumberAnimation { to: 0.9; duration: 900; easing.type: Easing.InOutSine } // design-lint: allow token-literal-duration: a star's twinkle, not interface motion
                NumberAnimation { to: 0; duration: 1300; easing.type: Easing.InOutSine } // design-lint: allow token-literal-duration: a star's twinkle, not interface motion
            }
        }
    }
}
