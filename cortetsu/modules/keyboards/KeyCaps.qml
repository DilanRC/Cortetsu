pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A chord drawn as keycaps: "SUPER + ALT + I" -> [SUPER] [ALT] [I].
Flow {
    id: root

    property var parts: []
    // Held right now (capture): drawn in the accent.
    property bool live: false
    property bool dim: false
    property string placeholder: ""

    spacing: CortetsuDesign.spacingUnit

    CortetsuText {
        visible: root.parts.length === 0 && root.placeholder.length > 0
        text: root.placeholder
        textSize: CortetsuTypography.labelMediumPx
        color: CortetsuDesign.colorOnSurfaceVariant
        height: 30
        verticalAlignment: Text.AlignVCenter
    }

    Repeater {
        model: root.parts

        delegate: KeyCap {
            required property string modelData
            text: modelData
            live: root.live
            dim: root.dim
        }
    }
}
