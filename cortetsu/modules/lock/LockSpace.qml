import QtQuick
import "../../theme"

// Deep space over the static wallpaper (Nebula's lock composition, drawn
// here from scratch): a dark veil, clouds of the accent colour and a field
// of stars. Painted once per size and colour; it never animates, so it
// costs nothing while the screen is locked.
Item {
    id: root

    property color tone: CortetsuDesign.colorPrimary
    property color glow: CortetsuDesign.colorIndicator

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.02, 0.06, 0.78)
    }

    Canvas {
        id: sky
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onToneChanged(): void { sky.requestPaint(); }
        }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            // Clouds: wide soft radial glows of the accent.
            const clouds = [[0.22, 0.30, 0.42, 0.20], [0.80, 0.24, 0.36, 0.16], [0.55, 0.78, 0.50, 0.14], [0.10, 0.85, 0.30, 0.10]];
            for (const c of clouds) {
                const g = ctx.createRadialGradient(w * c[0], h * c[1], 0, w * c[0], h * c[1], Math.max(w, h) * c[2]);
                g.addColorStop(0, Qt.alpha(root.tone, c[3]));
                g.addColorStop(0.5, Qt.alpha(root.glow, c[3] * 0.35));
                g.addColorStop(1, "transparent");
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, w, h);
            }
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
