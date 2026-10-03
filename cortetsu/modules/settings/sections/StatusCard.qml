pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: status

    required property string title
    required property string value
    property string detail: ""
    property string icon: "info"
    property bool activeState: false
    property bool warningState: false

    Layout.fillWidth: true
    implicitHeight: 78
    radiusValue: CortetsuDesign.radiusMedium
    baseColor: activeState
        ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42)
        : warningState
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.08)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
    outlined: true
    outlineColor: activeState
        ? Qt.alpha(CortetsuDesign.colorPrimary, 0.30)
        : warningState
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.36)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: status.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: status.warningState
                ? CortetsuDesign.colorWarning
                : status.activeState
                    ? CortetsuDesign.colorPrimary
                    : CortetsuDesign.colorOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            CortetsuText {
                text: status.title
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
            CortetsuText {
                Layout.fillWidth: true
                text: status.value
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            CortetsuText {
                Layout.fillWidth: true
                visible: status.detail.length > 0
                text: status.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }
}
