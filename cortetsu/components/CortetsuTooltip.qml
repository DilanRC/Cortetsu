import QtQuick
import QtQuick.Controls
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

ToolTip {
    id: root

    property Item target: null
    property bool hovered: false
    property bool focused: false

    parent: root.target
    visible: root.target !== null
        && root.text.length > 0
        && (root.hovered || root.focused)
    delay: CortetsuDesign.motionDeliberateMs
    leftPadding: CortetsuDesign.spacingStandard
    rightPadding: CortetsuDesign.spacingStandard
    topPadding: CortetsuDesign.spacingCompact
    bottomPadding: CortetsuDesign.spacingCompact

    background: CortetsuSurface {
        radiusValue: CortetsuDesign.radiusSmall
        baseColor: CortetsuDesign.colorTetsu
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.32)
        outlined: true
    }

    contentItem: CortetsuText {
        text: root.text
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorWashi
        elide: Text.ElideRight
    }
}
