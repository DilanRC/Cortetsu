import QtQuick
import QtQuick.Layouts
import "../modules/CortetsuDesign.js" as CortetsuDesign
import "../modules/CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property int index
    focus: root.index === 0 && !root.disabled
    activeFocusOnTab: !root.disabled

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string trailingIcon: "chevron_right"
    property bool selected: false
    property bool danger: false
    property bool disabled: false
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    signal clicked()

    implicitHeight: 58
    opacity: root.disabled ? 0.46 : 1

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: false
        disabled: root.disabled
        focused: root.activeFocus
        hovered: root.hovered
        pressed: root.pressed
        baseColor: root.danger
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.08)
            : CortetsuDesign.colorSurface
        hoverColor: root.danger
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.14)
            : CortetsuDesign.colorSurfaceHigh
        activeColor: root.danger
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.20)
            : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.48)
        outlined: root.selected
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.86)
            : root.danger
                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.72)
                : Qt.alpha(CortetsuDesign.colorPrimary, 0.72)
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            text: root.icon
            iconSize: CortetsuTypography.iconMediumPx
            color: root.danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            CortetsuText {
                Layout.fillWidth: true
                text: root.title
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                color: root.selected && root.danger
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorOnSurface
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                text: root.subtitle
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        CortetsuIcon {
            text: root.trailingIcon
            iconSize: CortetsuTypography.iconSmallPx
            color: root.selected
                ? (root.danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorWarning)
                : CortetsuDesign.colorOnSurfaceVariant
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
