import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One of the three power profiles. Used where a profile is applied and where
// it is assigned to a rule.
Item {
    id: root

    property string profile: ""
    property bool selected: false
    property bool busy: false
    property bool disabled: false
    property string note: ""
    readonly property string label: ({
        "power-saver": qsTr("Ahorro"),
        "balanced": qsTr("Equilibrado"),
        "performance": qsTr("Rendimiento")
    })[root.profile] ?? root.profile
    readonly property string glyph: root.profile === "power-saver"
        ? "eco"
        : root.profile === "performance" ? "speed" : "balance"

    signal chosen()

    implicitHeight: 64
    enabled: !root.disabled
    opacity: root.disabled ? 0.46 : 1
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.note ? `${root.label}. ${root.note}` : root.label
    Accessible.checked: root.selected
    Accessible.onPressAction: root.chosen()

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: root.selected
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        focused: root.activeFocus
        outlined: root.selected
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
        hoverColor: root.selected
            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.88)
            : CortetsuDesign.colorSurfaceHigh
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.76)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : Qt.alpha(CortetsuDesign.colorPrimary, 0.46)
    }

    CortetsuIcon {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.verticalCenter: parent.verticalCenter
        text: root.busy ? "progress_activity" : root.glyph
        color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceMuted
        iconSize: CortetsuTypography.iconMediumPx

        RotationAnimation on rotation {
            running: root.busy
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
            onRunningChanged: if (!running) icon.rotation = 0
        }
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.right: parent.right
        anchors.rightMargin: CortetsuDesign.spacingStandard
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        CortetsuText {
            width: parent.width
            text: root.label
            color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
            textSize: CortetsuTypography.bodyPx
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            visible: root.note.length > 0
            text: root.note
            color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.chosen()
    }

    Keys.onEnterPressed: root.chosen()
    Keys.onReturnPressed: root.chosen()
    Keys.onSpacePressed: root.chosen()
}
