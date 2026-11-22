import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A small round reading over the clock (Nebula's orbiting bubbles): the sky,
// the moon, the battery. `ring` < 0 draws no ring.
Item {
    id: root

    property string glyph: ""
    property string glyphFamily: ""
    property string text: ""
    property real ring: -1

    implicitWidth: 84
    implicitHeight: 84

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.86)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorPrimary, 0.3)
    }
    CortetsuRingGauge {
        anchors.fill: parent
        anchors.margins: 4
        visible: root.ring >= 0
        value: root.ring
        label: ""
        pending: ""
        opacity: 0.9
    }
    Column {
        anchors.centerIn: parent
        visible: root.ring < 0
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.glyph
            font.family: root.glyphFamily.length > 0 ? root.glyphFamily : font.family
            textSize: 26
            color: CortetsuDesign.colorOnPrimaryContainer
        }
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text.length > 0
            text: root.text
            textSize: CortetsuTypography.labelSmallPx
            color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.8)
        }
    }
}
