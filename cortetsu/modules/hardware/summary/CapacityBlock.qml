pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../Format.js" as Format

// A level that fills up: how full, how much, and what is left.
NavBlock {
    id: root

    property string icon: ""
    property string title: ""
    property var usage: null
    property string amount: ""
    property string footnote: ""
    property string severity: ""

    height: 108
    padding: CortetsuDesign.spacingStandard
    accessibleName: `${root.title} ${Format.percent(root.usage)}. ${root.footnote}`

    SummaryLabel {
        id: label
        icon: root.icon
        text: root.title
    }

    CortetsuText {
        id: figure
        anchors.left: parent.left
        anchors.top: label.bottom
        width: 76
        text: Format.percent(root.usage)
        textSize: CortetsuTypography.displaySmallPx
        font.weight: Font.DemiBold
    }

    CortetsuText {
        anchors.left: figure.right
        anchors.right: parent.right
        anchors.baseline: figure.baseline
        text: root.amount
        color: CortetsuDesign.colorOnSurfaceMuted
        textSize: CortetsuTypography.bodyLargePx
        elide: Text.ElideRight
    }

    CortetsuProgressBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: figure.bottom
        anchors.topMargin: CortetsuDesign.spacingUnit
        value: Format.fraction(root.usage)
        fillColor: root.severity ? flag.color : CortetsuDesign.colorPrimary
        barHeight: 6
    }

    SeverityIcon {
        id: flag
        anchors.left: parent.left
        anchors.verticalCenter: note.verticalCenter
        severity: root.severity
        iconSize: CortetsuTypography.labelMediumPx + 4
    }

    CortetsuText {
        id: note
        anchors.left: flag.visible ? flag.right : parent.left
        anchors.leftMargin: flag.visible ? CortetsuDesign.spacingUnit : 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: root.footnote
        color: root.severity ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.labelMediumPx
        elide: Text.ElideRight
    }
}
