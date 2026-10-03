pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: hero

    required property string icon
    required property string title
    required property string detail
    required property string value
    property string meta: ""
    property real progress: -1
    property color accentColor: CortetsuDesign.colorPrimary
    property bool warningState: false

    Layout.fillWidth: true
    implicitHeight: 112
    radiusValue: CortetsuDesign.radiusMedium
    baseColor: warningState
        ? Qt.alpha(CortetsuDesign.colorWarning, 0.10)
        : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42)
    outlineColor: warningState
        ? Qt.alpha(CortetsuDesign.colorWarning, 0.42)
        : Qt.alpha(accentColor, 0.42)
    outlined: true

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuSurface {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: warningState
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.16)
                : Qt.alpha(hero.accentColor, 0.18)
            outlined: false

            CortetsuIcon {
                anchors.centerIn: parent
                text: hero.icon
                iconSize: CortetsuTypography.iconLargePx
                color: hero.warningState ? CortetsuDesign.colorWarning : hero.accentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            CortetsuText {
                Layout.fillWidth: true
                text: hero.title
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                text: hero.detail
                textSize: CortetsuTypography.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                visible: hero.meta.length > 0
                text: hero.meta
                textSize: CortetsuTypography.labelSmallPx
                color: hero.warningState ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.minimumWidth: 128
            Layout.alignment: Qt.AlignVCenter
            spacing: CortetsuDesign.spacingCompact

            CortetsuText {
                Layout.fillWidth: true
                text: hero.value
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            CortetsuProgressBar {
                visible: hero.progress >= 0
                Layout.fillWidth: true
                value: Math.max(0, Math.min(1, hero.progress))
                fillColor: hero.warningState ? CortetsuDesign.colorWarning : hero.accentColor
                barHeight: 5
            }
        }
    }
}
