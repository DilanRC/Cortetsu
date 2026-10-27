import QtQuick
import "../theme"

ColorAnimation {
    duration: CortetsuDesign.motionPopoverMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: CortetsuDesign.easeOut
}
