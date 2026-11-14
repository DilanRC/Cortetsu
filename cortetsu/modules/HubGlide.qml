import QtQuick
import "../theme"

// Islands that grow or appear glide to their new place. See HubLean.qml for
// why this is a file and not an inline component.
NumberAnimation {
    duration: CortetsuDesign.motionStandardMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: CortetsuDesign.easeOut
}
