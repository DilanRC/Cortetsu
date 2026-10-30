import QtQuick
import QtQuick.Layouts
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    focus: false
    enabled: root.clickable && !root.disabled
    activeFocusOnTab: true

    Accessible.role: root.clickable ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.label
    Accessible.description: root.detail
    Accessible.focusable: root.clickable && !root.disabled
    Accessible.focused: root.activeFocus
    Accessible.onPressAction: if (root.clickable && !root.disabled) root.activated()

    property string label: ""
    property string icon: ""
    property string detail: ""
    property bool highlighted: false
    property bool warning: false
    property bool clickable: true
    property bool disabled: false
    // A kanji pressed as a seal in the corner while the tile is on.
    property string seal: ""
    readonly property bool hovered: root.clickable && mouse.containsMouse
    readonly property bool pressed: root.clickable && mouse.pressed
    signal activated()

    onHighlightedChanged: if (highlighted && seal !== "") hanko.stamp()

    implicitHeight: 76
    opacity: root.disabled ? 0.46 : 1

    // Press feedback scales the painted content only; the hitbox stays put.
    property real visualScale: root.pressed ? CortetsuDesign.pressScale : 1
    Behavior on visualScale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    CortetsuSurface {
        scale: root.visualScale
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: false
        disabled: root.disabled
        focused: root.activeFocus
        hovered: root.hovered
        pressed: root.pressed
        // Ink: an off tile is bare paper with a hairline; an on tile takes a
        // wash of the indicator colour.
        baseColor: root.warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.10)
            : root.highlighted
                ? Qt.alpha(CortetsuDesign.colorIndicator, 0.16)
                : Qt.alpha(CortetsuDesign.colorWashi, 0.03)
        hoverColor: root.warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.16)
            : root.highlighted
                ? Qt.alpha(CortetsuDesign.colorIndicator, 0.24)
                : Qt.alpha(CortetsuDesign.colorWashi, 0.07)
        activeColor: root.warning
            ? Qt.alpha(CortetsuDesign.colorWarning, 0.22)
            : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.92)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : root.warning
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.44)
                : root.highlighted
                    ? Qt.alpha(CortetsuDesign.colorIndicator, 0.34)
                    : Qt.alpha(CortetsuDesign.colorWashi, 0.08)
        outlined: true
    }

    RowLayout {
        scale: root.visualScale
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: root.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: root.warning
                ? CortetsuDesign.colorWarning
                : root.highlighted
                    ? CortetsuDesign.colorPrimary
                    : CortetsuDesign.colorOnSurface
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            CortetsuText {
                Layout.fillWidth: true
                text: root.label
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                text: root.detail
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        CortetsuHanko {
            id: hanko
            Layout.alignment: Qt.AlignTop
            size: 28
            glyph: root.seal
            visible: root.seal !== "" && root.highlighted && !root.warning
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.clickable && !root.disabled
        hoverEnabled: enabled
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.activated()
    }

    Keys.onEnterPressed: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
}
