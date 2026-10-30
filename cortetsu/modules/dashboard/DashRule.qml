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

// A thin brush stroke between margin notes.
CortetsuBrushStroke {
    Layout.fillWidth: true
    Layout.preferredHeight: 3
    ink: CortetsuDesign.colorWashi
    inkAlpha: 0.1
}
