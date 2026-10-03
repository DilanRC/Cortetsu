import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// A line of secondary readings. Only the first one can be flagged, so a hot
// sensor does not paint the figures beside it. The flag is an icon plus
// weight: vermillion text at this size falls short of 4.5:1 on a block.
Row {
    id: root

    property string lead: ""
    property string rest: ""
    property string severity: ""
    property int textSize: CortetsuTypography.bodySmallPx

    // A Row has no baseline of its own; borrowing the text's lets the line sit
    // on the baseline of the figure beside it.
    baselineOffset: leadText.baselineOffset

    SeverityIcon {
        anchors.verticalCenter: leadText.verticalCenter
        severity: root.severity
        iconSize: root.textSize + 4
        rightPadding: 4
    }

    CortetsuText {
        id: leadText
        text: root.lead
        color: root.severity ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceMuted
        textSize: root.textSize
        font.weight: root.severity ? Font.DemiBold : Font.Normal
    }

    CortetsuText {
        text: root.lead && root.rest ? ` · ${root.rest}` : root.rest
        color: CortetsuDesign.colorOnSurfaceMuted
        textSize: root.textSize
    }
}
