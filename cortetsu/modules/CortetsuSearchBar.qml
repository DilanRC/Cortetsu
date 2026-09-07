import QtQuick
import QtQuick.Controls
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

TextField {
    id: root

    // Compatibility aliases consumed by launcher code inherited from the
    // original search contract. Keep them while the field itself is native.
    property alias searchIcon: root
    property alias clearIcon: root
    property alias bg: root

    implicitHeight: 48
    leftPadding: CortetsuDesign.spacingComfortable
    rightPadding: CortetsuDesign.spacingComfortable
    topPadding: CortetsuDesign.spacingStandard
    bottomPadding: CortetsuDesign.spacingStandard
    color: CortetsuDesign.colorOnSurface
    placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
    selectionColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.56)
    selectedTextColor: CortetsuDesign.colorWashi
    font.pixelSize: CortetsuTypography.bodyLargePx
    selectByMouse: true

    background: CortetsuSurface {
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.96)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.86)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.72)
            : root.hovered
                ? Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.24)
        outlined: true
        focused: root.activeFocus

        Behavior on baseColor {
            ColorAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }
}
