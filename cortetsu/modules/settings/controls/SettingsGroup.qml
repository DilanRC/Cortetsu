pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// One subject: a heading with its icon and the rows that belong to it. The
// rows share one panel and are told apart by a hairline, not a card each.
// A collapsible group keeps rarely used rows out of the way until asked.
ColumnLayout {
    id: root

    property string title: ""
    property string detail: ""
    property string icon: ""
    property bool collapsible: false
    property bool expanded: !collapsible
    // Without a panel the rows sit straight on the page: for chips, cards
    // and previews that carry their own surface.
    property bool panel: true
    default property alias rows: body.data

    Layout.fillWidth: true
    spacing: CortetsuDesign.spacingStandard

    Item {
        id: header
        Layout.fillWidth: true
        visible: root.title.length > 0
        implicitHeight: headerColumn.implicitHeight
        activeFocusOnTab: root.collapsible
        Accessible.role: root.collapsible ? Accessible.Button : Accessible.Heading
        Accessible.name: root.title
        Accessible.description: root.detail
        Accessible.onPressAction: root.toggle()

        function toggleOrIgnore(): void { if (root.collapsible) root.toggle(); }
        Keys.onSpacePressed: toggleOrIgnore()
        Keys.onReturnPressed: toggleOrIgnore()
        Keys.onEnterPressed: toggleOrIgnore()

        TapHandler {
            enabled: root.collapsible
            onTapped: root.toggle()
        }
        HoverHandler {
            enabled: root.collapsible
            cursorShape: Qt.PointingHandCursor
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: CortetsuDesign.radiusSmall
            visible: header.activeFocus
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.82)
        }

        ColumnLayout {
            id: headerColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuIcon {
                    visible: root.icon.length > 0
                    text: root.icon
                    iconSize: CortetsuTypography.iconSmallPx
                    color: CortetsuDesign.colorPrimary
                }

                CortetsuText {
                    objectName: "groupTitle"
                    Layout.fillWidth: true
                    text: CortetsuDesign.labelCaps ? root.title.toUpperCase() : root.title
                    textSize: CortetsuDesign.labelCaps ? CortetsuTypography.labelLargePx : CortetsuTypography.titleSmallPx
                    font.family: CortetsuDesign.fontHeading
                    font.weight: CortetsuDesign.headingWeight
                    font.letterSpacing: CortetsuDesign.labelTracking
                    elide: Text.ElideRight
                }

                CortetsuIcon {
                    visible: root.collapsible
                    text: "expand_more"
                    iconSize: CortetsuTypography.iconSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation {
                        NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut }
                    }
                }
            }

            CortetsuText {
                Layout.fillWidth: true
                Layout.leftMargin: root.icon.length > 0 ? CortetsuTypography.iconSmallPx + CortetsuDesign.spacingCompact : 0
                visible: text.length > 0
                text: root.detail
                textSize: CortetsuTypography.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    function toggle(): void {
        root.expanded = !root.expanded;
    }

    // Washi lifts its sheets off the page with a soft shadow, not a line.
    Item {
        Layout.fillWidth: true
        visible: root.expanded
        implicitHeight: body.implicitHeight

        Rectangle {
            visible: root.panel && CortetsuDesign.materialStyle === 1
            anchors.fill: parent
            anchors.topMargin: 3
            anchors.bottomMargin: -3
            radius: CortetsuDesign.radiusMedium
            color: Qt.alpha(CortetsuDesign.colorOnSurface, CortetsuDesign.materialShadowAlpha * 0.4)
        }

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: root.panel ? Qt.alpha(CortetsuDesign.colorSurfaceGlass, CortetsuDesign.materialStyle === 1 ? 0.6 : 0.72) : "transparent"
            outlined: root.panel
            outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, CortetsuDesign.materialStyle === 1 ? 0.3
                : CortetsuDesign.materialStyle === 2 ? 0.85 : 0.48)
        }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.panel ? 0 : CortetsuDesign.spacingStandard
        }
    }
}
