import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One domain of the control center as a card: a heading line with its
// state, and the domain's controls under it. The chevron, when given, leads
// to that domain's page in Ajustes.
Item {
    id: card

    property string icon: ""
    property string title: ""
    property string detail: ""
    property string actionTooltip: ""
    property bool attention: false
    default property alias content: body.data
    signal actionRequested()

    implicitHeight: column.implicitHeight + CortetsuDesign.spacingStandard * 2

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: card.attention ? Qt.alpha(CortetsuDesign.colorWarning, 0.08) : Qt.alpha(CortetsuDesign.colorWashi, 0.035)
        outlineColor: card.attention ? Qt.alpha(CortetsuDesign.colorWarning, 0.36) : Qt.alpha(CortetsuDesign.colorWashi, 0.10)
        outlined: true
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            visible: card.title.length > 0
            spacing: CortetsuDesign.spacingCompact

            CortetsuIcon {
                text: card.icon
                iconSize: CortetsuTypography.iconSmallPx
                color: card.attention ? CortetsuDesign.colorWarning : CortetsuDesign.colorPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    Layout.fillWidth: true
                    text: card.title
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    visible: card.detail.length > 0
                    text: card.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
            CortetsuButton {
                visible: card.actionTooltip.length > 0
                compact: true
                icon: "chevron_right"
                label: ""
                tooltipText: card.actionTooltip
                onClicked: card.actionRequested()
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact
        }
    }
}
