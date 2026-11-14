import QtQuick
import "../theme"

// An engaged island leans 2 px towards its popout.
// A file of its own, not an inline component of CortetsuBottomHubView: a soft
// reload keeps the previous generation's types for a file at the same path,
// and an inline component added to such a file is "not a type" until restart.
Translate {
    required property bool engaged
    required property var inward

    x: engaged ? 2 * inward.x : 0
    y: engaged ? 2 * inward.y : 0
    Behavior on x { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
    Behavior on y { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
}
