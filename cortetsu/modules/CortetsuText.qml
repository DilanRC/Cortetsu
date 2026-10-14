import QtQuick
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography

Text {
    id: root

    property bool animate: false
    property int textSize: CortetsuTypography.bodyPx

    color: CortetsuDesign.colorWashi
    font.family: CortetsuTypography.uiFamily
    font.pixelSize: textSize
    font.weight: Font.Normal
    renderType: Text.NativeRendering
    antialiasing: true

    Behavior on text {
        enabled: root.animate

        SequentialAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: CortetsuDesign.motionFastMs }
            PropertyAction {}
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: CortetsuDesign.motionStandardMs }
        }
    }
}
