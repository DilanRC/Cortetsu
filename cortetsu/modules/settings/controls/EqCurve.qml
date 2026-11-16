pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../../../services/EqResponse.js" as EqResponse

// The response the ten sliders add up to, drawn from the same biquad maths
// that sizes the preamp. It is what the ear gets (overlap included), so a
// curve that looks flat is flat. Repainted on a change, never per frame.
Item {
    id: root

    property var frequencies: []
    property var gains: []
    property real preamp: 0
    readonly property real rangeDb: 15

    implicitHeight: 112
    Accessible.role: Accessible.Graphic
    Accessible.name: qsTr("Curva del ecualizador, pico de %1 dB").arg(EqResponse.peakDb(root.frequencies, root.gains).toFixed(1))

    onGainsChanged: canvas.requestPaint()
    onPreampChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingComfortable + 28
        anchors.rightMargin: CortetsuDesign.spacingComfortable
        anchors.topMargin: CortetsuDesign.spacingStandard
        anchors.bottomMargin: CortetsuDesign.spacingStandard + 14
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        readonly property color lineColor: CortetsuDesign.colorPrimary
        readonly property color gridColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, CortetsuDesign.materialSeparatorAlpha)
        readonly property color netColor: Qt.alpha(CortetsuDesign.colorOnSurfaceVariant, 0.7)
        onLineColorChanged: requestPaint()
        onGridColorChanged: requestPaint()

        function yFor(db: real): real {
            return height / 2 - Math.max(-root.rangeDb, Math.min(root.rangeDb, db)) / root.rangeDb * (height / 2);
        }

        function xFor(hz: real): real {
            return Math.log(hz / 20) / Math.log(1000) * width;
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 1;
            ctx.strokeStyle = gridColor;
            for (const db of [-12, 0, 12]) {
                ctx.beginPath();
                ctx.moveTo(0, yFor(db));
                ctx.lineTo(width, yFor(db));
                ctx.stroke();
            }
            if (!root.frequencies.length)
                return;
            const steps = Math.max(32, Math.round(width / 3));
            const trace = (offset, colour, lineWidth) => {
                ctx.beginPath();
                for (let i = 0; i <= steps; i++) {
                    const hz = 20 * Math.pow(1000, i / steps);
                    const y = yFor(EqResponse.cascadeDb(root.frequencies, root.gains, hz) + offset);
                    if (i === 0)
                        ctx.moveTo(0, y);
                    else
                        ctx.lineTo(i / steps * width, y);
                }
                ctx.strokeStyle = colour;
                ctx.lineWidth = lineWidth;
                ctx.stroke();
            };
            // What leaves the node: the curve lowered by the preamp. It
            // stays at or under the 0 dB line.
            if (root.preamp < 0)
                trace(root.preamp, netColor, 1);
            trace(0, lineColor, 2);
        }
    }

    Repeater {
        model: [12, 0, -12]
        delegate: CortetsuText {
            required property int modelData
            x: CortetsuDesign.spacingComfortable
            y: canvas.y + canvas.yFor(modelData) - height / 2
            text: modelData > 0 ? `+${modelData}` : `${modelData}`
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }

    Repeater {
        model: [100, 1000, 10000]
        delegate: CortetsuText {
            required property int modelData
            x: canvas.x + canvas.xFor(modelData) - width / 2
            y: canvas.y + canvas.height + 2
            text: modelData >= 1000 ? `${modelData / 1000}k` : `${modelData}`
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }
}
