pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// The shared anatomy of a settings row: what it is, what it does, and on the
// right the control or the value. A row that reports a failure says so in
// place of its description.
Item {
    id: root

    property string title: ""
    property string detail: ""
    // "" | "busy" | "error"
    property string status: ""
    property string statusText: ""
    // Set by the rows that react to a click anywhere on them.
    property bool interactive: false
    property bool disabled: false
    readonly property bool hovered: hover.hovered
    // Children of a row go to its right-hand slot, so the handlers for the
    // row as a whole live here and report through this signal.
    signal clicked()
    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(CortetsuDesign.rowHeight, labels.implicitHeight + CortetsuDesign.spacingStandard * 2)

    HoverHandler {
        id: hover
        enabled: root.interactive && !root.disabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.interactive && !root.disabled
        onTapped: root.clicked()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: CortetsuDesign.radiusSmall
        color: CortetsuDesign.colorOnSurface
        opacity: root.hovered ? 0.05 : 0
        Behavior on opacity {
            NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
        }
    }

    // The first row of a group sits at y 0 and needs no line above it.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        visible: root.y > 0
        height: 1
        color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.36)
    }

    Rectangle {
        objectName: "focusRing"
        anchors.fill: parent
        anchors.margins: 2
        radius: CortetsuDesign.radiusSmall
        visible: root.activeFocus
        color: "transparent"
        border.width: 2
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.82)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard
        opacity: root.disabled ? 0.52 : 1

        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            spacing: 1

            CortetsuText {
                Layout.fillWidth: true
                text: root.title
                textSize: CortetsuTypography.bodyPx
                elide: Text.ElideRight
            }

            CortetsuText {
                objectName: "rowDetail"
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.status === "error" && root.statusText.length > 0
                    ? root.statusText
                    : root.status === "busy" && root.statusText.length > 0
                        ? root.statusText
                        : root.detail
                textSize: CortetsuTypography.labelSmallPx
                color: root.status === "error"
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: trailingSlot
            Layout.alignment: Qt.AlignVCenter
            spacing: CortetsuDesign.spacingCompact
        }
    }
}
