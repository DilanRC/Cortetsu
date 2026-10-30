import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

// A seal: vermillion pressed into the paper, the glyph carved out of it. It
// is the one place vermillion appears, so it marks what matters: the zone
// you are in, a recording, something urgent. stamp() presses it again.
Item {
    id: root
    property string glyph: "今"
    property real size: 44
    // Vermillion, leaning a little towards the wallpaper so it belongs.
    property color ink: Qt.tint(CortetsuDesign.colorVermillion, Qt.alpha(CortetsuDesign.colorPrimary, 0.22))
    implicitWidth: size
    implicitHeight: size

    function stamp(): void { press.restart(); }

    Item {
        id: seal
        anchors.fill: parent
        rotation: -4
        transformOrigin: Item.Center

        Rectangle {
            anchors.fill: parent
            radius: root.size * 0.12
            color: root.ink
        }
        // The carved inner border of a real seal.
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.size * 0.09
            radius: root.size * 0.06
            color: "transparent"
            border.width: Math.max(1, root.size * 0.035)
            border.color: Qt.alpha(CortetsuDesign.colorSumi, 0.55)
        }
        Text {
            anchors.centerIn: parent
            text: root.glyph
            font.family: CortetsuTypography.kanjiFamily
            font.weight: Font.Black
            font.pixelSize: root.size * 0.52
            color: Qt.alpha(CortetsuDesign.colorSumi, 0.88)
        }
        CortetsuGrain { anchors.fill: parent; radius: root.size * 0.12; strength: 0.22 }
    }

    // Pressed down: from a little large and tilted, onto the paper.
    ParallelAnimation {
        id: press
        NumberAnimation { target: seal; property: "scale"; from: 1.35; to: 1; duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutQuint }
        NumberAnimation { target: seal; property: "rotation"; from: -14; to: -4; duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutQuint }
        NumberAnimation { target: seal; property: "opacity"; from: 0; to: 1; duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
    }
}
