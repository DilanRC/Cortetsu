import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

// A reading as a ring (08-widgets): the arc is the value, the centre says it.
// value < 0 is "no reading yet": an empty track and `pending` in the centre.
Item {
    id: root

    property real value: -1
    property string label: ""
    property string pending: "…"
    property color tone: value > 0.9 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
    property real thickness: Math.max(3, width * 0.08)

    implicitWidth: 76
    implicitHeight: 76

    onValueChanged: canvas.requestPaint()
    onToneChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = Math.min(width, height) / 2 - root.thickness / 2;
            const start = Math.PI * 0.75;
            const sweep = Math.PI * 1.5;
            ctx.lineCap = "round";
            ctx.lineWidth = root.thickness;
            ctx.strokeStyle = Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.4);
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, start, start + sweep);
            ctx.stroke();
            if (root.value > 0) {
                ctx.strokeStyle = root.tone;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, start, start + sweep * Math.min(1, root.value));
                ctx.stroke();
            }
        }
    }

    Column {
        anchors.centerIn: parent
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.value >= 0 ? `${Math.round(root.value * 100)} %` : root.pending
            textSize: Math.round(root.width * 0.2)
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            textSize: Math.max(9, Math.round(root.width * 0.14))
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }
}
