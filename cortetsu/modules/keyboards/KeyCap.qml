import QtQuick
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One key drawn as a keycap, with its lower edge so it reads as a key and
// not a chip. Used by KeyCaps (wrapping chords) and the shortcut sheet.
Rectangle {
    id: cap

    property string text: ""
    // Held right now (capture): drawn in the accent.
    property bool live: false
    property bool dim: false

    width: Math.max(30, capText.implicitWidth + 16)
    height: 30
    radius: CortetsuDesign.radiusSmall
    color: live ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorSumi, 0.6)
    border.width: 1
    border.color: live ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.6)
    opacity: dim ? 0.55 : 1
    Accessible.ignored: true

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 3
        radius: CortetsuDesign.radiusSmall
        color: Qt.alpha(CortetsuDesign.colorSumi, cap.live ? 0.25 : 0.55)
    }

    CortetsuText {
        id: capText
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        text: cap.text
        textSize: CortetsuTypography.labelMediumPx
        font.weight: Font.DemiBold
        color: cap.live ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface
    }
}
