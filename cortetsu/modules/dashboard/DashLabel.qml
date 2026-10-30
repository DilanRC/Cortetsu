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

CortetsuText {
    textSize: CortetsuTypography.labelSmallPx
    color: CortetsuDesign.colorOnSurfaceVariant
    font.weight: Font.DemiBold
    font.letterSpacing: 0.8
}
