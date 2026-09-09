import QtQuick
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

Text {
    id: root

    property int iconSize: CortetsuTypography.iconMediumPx
    property real fill: 0
    property int grade: 0
    property bool animate: false
    property font fontStyle: Qt.font({
        family: CortetsuTypography.iconFamily,
        pixelSize: iconSize,
        weight: Font.Normal
    })

    color: CortetsuDesign.colorOnSurface
    font: fontStyle
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
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
