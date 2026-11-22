import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../../services"
import ".."

// The centre of the lock: a twelve-lobed disc that turns very slowly, with
// the mark, the time and the date inside (Nebula's clock composition, drawn
// here with a Canvas). A rejected attempt flashes it vermillion; an accepted
// one turns the mark Cosmic and lights the disc before the release.
Item {
    id: root

    required property string phase
    property bool rejected: false
    property bool accepted: false
    property real flash: 0

    function flashRejected(): void {
        if (!CortetsuDesign.reducedMotion)
            flashAnim.restart();
    }

    readonly property color fill: Qt.tint(Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.94),
        Qt.alpha(CortetsuDesign.colorVermillion, Math.max(root.flash, root.rejected ? 0.28 : 0)))

    onFillChanged: disc.requestPaint()
    onWidthChanged: disc.requestPaint()

    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: root; property: "flash"; to: 1; duration: 80 } // design-lint: allow token-literal-duration: a short flash, then a slow fade
        NumberAnimation { target: root; property: "flash"; to: 0; duration: 600; easing.type: Easing.OutCubic } // design-lint: allow token-literal-duration: fade of the flash
    }

    // The light of acceptance: a halo that grows out of the disc.
    Rectangle {
        objectName: "lockAcceptedHalo"
        anchors.centerIn: parent
        width: parent.width * (root.accepted ? 1.45 : 1)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: root.accepted ? 18 : 0
        border.color: Qt.alpha(CortetsuDesign.colorSuccess, root.accepted ? 0.35 : 0)
        opacity: root.accepted ? 1 : 0
        Behavior on width { enabled: !CortetsuDesign.reducedMotion; NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } // design-lint: allow token-literal-duration: fits the 900 ms hold
        Behavior on opacity { NumberAnimation { duration: 250 } } // design-lint: allow token-literal-duration: fits the 900 ms hold
    }

    Canvas {
        id: disc
        anchors.fill: parent
        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 60000
            loops: Animation.Infinite
            running: root.visible && !CortetsuDesign.reducedMotion
        }
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2, base = Math.min(width, height) / 2 - 4;
            ctx.beginPath();
            for (let i = 0; i <= 240; ++i) {
                const a = i / 240 * Math.PI * 2;
                const r = base * (0.94 + 0.06 * Math.cos(12 * a));
                const x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.closePath();
            ctx.fillStyle = root.accepted ? Qt.tint(root.fill, Qt.alpha(CortetsuDesign.colorSuccess, 0.22)) : root.fill;
            ctx.fill();
            ctx.lineWidth = 2;
            ctx.strokeStyle = Qt.alpha(root.rejected || root.flash > 0.1 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary, 0.6);
            ctx.stroke();
        }
    }
    onAcceptedChanged: disc.requestPaint()
    onRejectedChanged: disc.requestPaint()

    Column {
        anchors.centerIn: parent
        spacing: 2

        CortetsuEvolvingMark {
            id: mark
            objectName: "lockMark"
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width * 0.22
            height: width
            phase: root.phase
            animated: !CortetsuDesign.reducedMotion
            monochrome: true
            monochromeColor: root.rejected ? CortetsuDesign.colorVermillion
                : root.accepted ? CortetsuDesign.colorSuccess : CortetsuDesign.colorOnPrimaryContainer
        }
        CortetsuText {
            objectName: "lockClock"
            anchors.horizontalCenter: parent.horizontalCenter
            text: Time.timeStr
            textSize: Math.round(root.width * 0.22)
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
            color: CortetsuDesign.colorOnPrimaryContainer
        }
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: CortetsuRegional.formatDate(Time.date, "longDay", true)
            textSize: Math.round(root.width * 0.055)
            color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.75)
        }
    }
}
