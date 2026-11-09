import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    // Selection cards participate in Tab order without taking focus on load.
    focus: false
    enabled: !disabled
    activeFocusOnTab: true

    Accessible.role: Accessible.RadioButton
    Accessible.name: root.title
    Accessible.description: root.subtitle
    Accessible.checkable: true
    Accessible.checked: root.selected
    Accessible.focusable: !root.disabled
    Accessible.focused: root.activeFocus
    Accessible.onPressAction: if (!root.disabled) root.clicked()
    Accessible.onToggleAction: if (!root.disabled) root.clicked()

    property string title: ""
    property string subtitle: ""
    property var swatches: []
    // Shown instead of the squares when none has a colour (a scheme derived
    // from the wallpaper has no fixed palette to preview).
    property string swatchFallback: qsTr("Sin colores fijos")
    readonly property bool hasSwatches: root.swatches.some(colour => String(colour) !== "transparent")
    property bool selected: false
    property bool disabled: false
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    property real visualScale: root.pressed
        ? CortetsuDesign.pressScale
        : root.hovered || root.activeFocus
            ? 1.008
            : 1

    signal clicked()

    implicitWidth: 192
    implicitHeight: 116
    opacity: root.disabled ? 0.46 : 1
    Behavior on visualScale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: root.selected
        disabled: root.disabled
        focused: root.activeFocus
        hovered: root.hovered
        pressed: root.pressed
        scale: root.visualScale
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.74)
        baseColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.74)
            : CortetsuDesign.colorSurfaceGlass
        hoverColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.84)
            : CortetsuDesign.colorSurfaceHigh
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : root.selected
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.58)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)
        outlined: true
    }

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingUnit
        scale: root.visualScale

        CortetsuText {
            width: parent.width
            text: root.title
            textSize: CortetsuTypography.bodyPx
            color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            text: root.subtitle
            textSize: CortetsuTypography.labelSmallPx
            color: root.selected
                ? CortetsuDesign.colorOnPrimaryContainer
                : CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }

        Item { width: 1; height: 1 }

        CortetsuText {
            objectName: "swatchFallback"
            visible: root.swatches.length > 0 && !root.hasSwatches
            height: 22
            verticalAlignment: Text.AlignVCenter
            text: root.swatchFallback
            textSize: CortetsuTypography.labelSmallPx
            color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
        }

        Row {
            visible: root.hasSwatches
            spacing: CortetsuDesign.spacingUnit

            // Counted, not handed the array: a new list of the same length
            // recolours these squares instead of rebuilding them.
            Repeater {
                model: root.swatches.length

                delegate: Rectangle {
                    required property int index
                    width: 22
                    height: 22
                    radius: CortetsuDesign.radiusSmall / 2
                    color: root.swatches[index] ?? "transparent"
                    // The theme's outline keeps a dark or light square visible
                    // on the card in every theme and scheme.
                    border.width: 1
                    border.color: Qt.alpha(CortetsuDesign.colorOutline, 0.72)
                }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.clicked()
    }

    Keys.onEnterPressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
