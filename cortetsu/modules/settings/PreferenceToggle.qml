pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: preference

    required property string title
    property string detail: ""
    property string icon: "tune"
    property bool checked: false
    property bool controlDisabled: false
    signal changed(bool checked)

    Layout.fillWidth: true
    implicitHeight: 68
    radiusValue: CortetsuDesign.radiusMedium
    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: preference.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: preference.checked ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            CortetsuText {
                Layout.fillWidth: true
                text: preference.title
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                visible: preference.detail.length > 0
                text: preference.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        CortetsuToggle {
            checked: preference.checked
            disabled: preference.controlDisabled
            onToggled: checked => preference.changed(checked)
        }
    }
}
