pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Rectangle {
    property color tint: CortetsuDesign.colorSurfaceHigh
    radius: CortetsuDesign.radiusLarge
    color: Qt.alpha(tint, 0.55)
    border.width: 1
    border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.05)
}
