import QtQuick
import QtQuick.Layouts
import "../"
import "../../components"
import "../../services"
import "../../utils"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: root

    required property var modelData
    required property var props
    required property bool expanded
    required property var screenState
    property bool hovered: false
    readonly property bool hasModelData: modelData !== null && modelData !== undefined
    readonly property bool closed: !hasModelData || modelData.closed
    readonly property int urgency: hasModelData ? modelData.urgency : 0
    readonly property string summary: hasModelData ? modelData.summary : ""
    readonly property string appName: hasModelData ? modelData.appName : ""
    readonly property string timeLabel: hasModelData ? modelData.timeStr : ""
    readonly property string imagePath: hasModelData ? modelData.image : ""
    readonly property string bodyText: hasModelData ? modelData.body : ""
    readonly property var notificationActions: hasModelData && modelData.actions ? modelData.actions : []
    readonly property bool urgent: urgency >= 2
    readonly property real nonAnimHeight: contentLayout.implicitHeight + CortetsuDesign.spacingComfortable * 2

    implicitHeight: nonAnimHeight
    radiusValue: CortetsuDesign.radiusMedium
    outlined: true
    focus: false
    activeFocusOnTab: true
    focused: root.activeFocus
    baseColor: root.urgent
        ? Qt.alpha(CortetsuDesign.colorVermillion, 0.10)
        : root.hovered
            ? Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.98)
            : Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.92)
    outlineColor: root.activeFocus
        ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
        : root.urgent
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.48)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, root.hovered ? 0.40 : 0.22)
    opacity: root.closed ? 0 : 1
    scale: root.closed ? 0.985 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.InCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    Component.onCompleted: if (root.hasModelData) root.modelData.lock(root)
    Component.onDestruction: if (root.hasModelData) root.modelData.unlock(root)

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        visible: root.urgent
        width: 2
        height: Math.max(28, parent.height - CortetsuDesign.spacingComfortable * 2)
        radius: 1
        color: CortetsuDesign.colorVermillion
        opacity: 0.88
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onPressed: root.forceActiveFocus()
        onClicked: root.expanded = !root.expanded
    }

    Keys.onEnterPressed: root.expanded = !root.expanded
    Keys.onReturnPressed: root.expanded = !root.expanded
    Keys.onSpacePressed: root.expanded = !root.expanded
    Keys.onEscapePressed: if (root.hasModelData) root.modelData.close()

    ColumnLayout {
        id: contentLayout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusSmall
                    baseColor: root.urgent
                        ? Qt.alpha(CortetsuDesign.colorVermillion, 0.13)
                        : Qt.alpha(CortetsuDesign.colorPrimary, 0.12)
                }

                CortetsuIcon {
                    anchors.centerIn: parent
                    text: Icons.getNotifIcon(root.summary, root.urgency)
                    iconSize: CortetsuTypography.iconMediumPx
                    color: root.urgent
                        ? CortetsuDesign.colorVermillion
                        : CortetsuDesign.colorPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.summary
                    textSize: CortetsuTypography.bodyLargePx
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: CortetsuDesign.colorOnSurface
                }

                CortetsuText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.appName || qsTr("System notification")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuText {
                text: root.timeLabel
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuSurface {
                visible: image.source.length > 0
                Layout.preferredWidth: visible ? 58 : 0
                Layout.preferredHeight: visible ? 58 : 0
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: CortetsuDesign.colorSurfaceGlass
                clip: true

                Image {
                    id: image
                    anchors.fill: parent
                    source: root.imagePath
                    sourceSize.width: 116
                    sourceSize.height: 116
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }
            }

            CortetsuText {
                id: body
                Layout.fillWidth: true
                text: root.bodyText
                textSize: CortetsuTypography.bodyPx
                maximumLineCount: root.expanded ? 8 : 2
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                visible: text.length > 0
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.notificationActions.length > 0 || root.hovered || root.expanded || root.activeFocus
            spacing: CortetsuDesign.spacingCompact

            Repeater {
                model: root.notificationActions
                delegate: CortetsuButton {
                    required property int index
                    Layout.fillWidth: false
                    compact: true
                    label: root.notificationActions[index] ? root.notificationActions[index].text : ""
                    onClicked: if (root.notificationActions[index]) root.notificationActions[index].invoke()
                }
            }

            Item { Layout.fillWidth: true }

            CortetsuButton {
                compact: true
                label: qsTr("Dismiss")
                icon: "close"
                danger: root.urgent
                onClicked: if (root.hasModelData) root.modelData.close()
            }
        }
    }
}
