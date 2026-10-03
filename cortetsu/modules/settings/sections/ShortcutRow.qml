pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: shortcut

    required property string keys
    required property string action
    property string detail: ""

    Layout.fillWidth: true
    implicitHeight: 58
    radiusValue: CortetsuDesign.radiusMedium
    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.66)
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.42)

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuSurface {
            Layout.preferredWidth: keyLabel.implicitWidth + CortetsuDesign.spacingStandard * 2
            Layout.preferredHeight: 30
            radiusValue: CortetsuDesign.radiusSmall
            baseColor: Qt.alpha(CortetsuDesign.colorSumi, 0.60)
            outlined: true
            outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.58)
            CortetsuText {
                id: keyLabel
                anchors.centerIn: parent
                text: shortcut.keys
                textSize: CortetsuTypography.labelSmallPx
                font.weight: Font.DemiBold
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            CortetsuText {
                Layout.fillWidth: true
                text: shortcut.action
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            CortetsuText {
                Layout.fillWidth: true
                visible: shortcut.detail.length > 0
                text: shortcut.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }
}
