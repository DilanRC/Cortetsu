import QtQuick
import "../theme"

// The hairline that tells rows and groups apart. Premium sobria separates by
// a line or by space before it reaches for another frame, so every such line
// reads its strength from one token.
Rectangle {
    property bool vertical: false

    implicitWidth: vertical ? CortetsuDesign.outlineWidth : 0
    implicitHeight: vertical ? 0 : CortetsuDesign.outlineWidth
    color: Qt.alpha(CortetsuDesign.colorOutlineVariant, CortetsuDesign.materialSeparatorAlpha)
    Accessible.ignored: true
}
