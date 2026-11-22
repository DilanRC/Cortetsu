import QtQuick
import "../../theme"
import "../../components"

// Deep space over the static wallpaper (Nebula's lock composition, drawn
// here from scratch): a dark veil, clouds of the accent colour (ink washes)
// and a field of stars painted once per size. Nothing animates, so it
// costs nothing while the screen is locked.
Item {
    id: root

    property color tone: CortetsuDesign.colorPrimary

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.02, 0.06, 0.78)
    }

    // Clouds: soft washes of the accent, through the one owner of washes.
    Repeater {
        model: [[0.22, 0.30, 0.14], [0.80, 0.24, 0.12], [0.55, 0.80, 0.10]]
        delegate: CortetsuInkPanel {
            required property var modelData
            anchors.fill: parent
            groundAlpha: 0
            grain: 0
            hairline: false
            marks: false
            wash: root.tone
            washAlpha: modelData[2]
            washX: modelData[0]
            washY: modelData[1]
        }
    }

    Canvas {
        id: sky
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            // Stars: a fixed pseudo-random field, the same on every paint.
            let seed = 7;
            const next = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
            for (let i = 0; i < 220; ++i) {
                const x = next() * w, y = next() * h, r = next() < 0.92 ? 0.7 : 1.6;
                ctx.fillStyle = Qt.rgba(0.92, 0.9, 1, 0.25 + next() * 0.6);
                ctx.beginPath();
                ctx.arc(x, y, r, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }
}
