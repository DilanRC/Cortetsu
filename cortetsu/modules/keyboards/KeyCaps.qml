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

        delegate: Rectangle {
            id: cap
            required property string modelData
            width: Math.max(30, capText.implicitWidth + 16)
            height: 30
            radius: CortetsuDesign.radiusSmall
            color: root.live ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorSumi, 0.6)
            border.width: 1
            border.color: root.live ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.6)
            opacity: root.dim ? 0.55 : 1

            // The key's lower edge, so a cap reads as a key and not a chip.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                height: 3
                radius: CortetsuDesign.radiusSmall
                color: Qt.alpha(CortetsuDesign.colorSumi, root.live ? 0.25 : 0.55)
            }

            CortetsuText {
                id: capText
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: cap.modelData
                textSize: CortetsuTypography.labelMediumPx
                font.weight: Font.DemiBold
                color: root.live ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface
            }
        }
    }
}
