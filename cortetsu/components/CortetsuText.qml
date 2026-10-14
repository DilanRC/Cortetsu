pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

Text {
    id: root

    property bool animate: false
    property int textSize: CortetsuTypography.bodyPx

    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    color: CortetsuDesign.colorOnSurface
    font.family: CortetsuTypography.uiFamily
    font.pixelSize: textSize
    font.weight: Font.Normal

    Behavior on color {
        ColorAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    Behavior on text {
        enabled: root.animate

        SequentialAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: CortetsuDesign.motionFastMs }
            PropertyAction {}
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: CortetsuDesign.motionStandardMs }
        }
    }
}
