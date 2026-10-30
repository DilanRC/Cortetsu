pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Serif text for the big moments of the ink language.
CortetsuText {
    font.family: CortetsuTypography.inkFamily
    font.weight: Font.Light
    textSize: CortetsuTypography.inkTitlePx
}
