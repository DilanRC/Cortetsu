import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"

// The large OSD is the canonical full system-control surface. The legacy
// The legacy compact host and Utilities card are not instantiated anywhere.
Item {
    id: root

    required property var monitor
    required property var screenState
    required property real volume
    required property bool muted
    required property real brightness
    required property ShellScreen screen
    property bool hovered: false

    // Wide layout (02-quick-settings): a navigation column, then three
    // columns of cards.
    readonly property int navWidth: content.expanded ? 212 : 0
    implicitWidth: content.expanded ? 1320 : 520
    implicitHeight: Math.max(content.implicitHeight, content.expanded ? nav.implicitHeight : 0) + CortetsuDesign.spacingSection * 2

    HoverHandler {
        onHoveredChanged: root.hovered = hovered
    }

    CortetsuPopupSurface {
        anchors.fill: parent
        ColumnLayout {
            id: nav
            objectName: "quickNav"
            visible: content.expanded
            x: CortetsuDesign.spacingSection
            y: CortetsuDesign.spacingSection + 56
            width: root.navWidth - CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingUnit
            Repeater {
                model: [
                    { id: "summary", icon: "dashboard", title: qsTr("Resumen") },
                    { id: "network", icon: "lan", title: qsTr("Conectividad") },
                    { id: "audio", icon: "graphic_eq", title: qsTr("Audio") },
                    { id: "notifications", icon: "notifications", title: qsTr("Notificaciones") },
                    { id: "power", icon: "bolt", title: qsTr("Energía") },
                    { id: "actions", icon: "apps", title: qsTr("Acciones") }
                ]
                delegate: CortetsuListRow {
                    required property var modelData
                    objectName: `quickNav-${modelData.id}`
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.title
                    selected: content.section === modelData.id
                    onClicked: content.section = modelData.id
                }
            }
        }

        FullContent {
            id: content
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingSection
            anchors.leftMargin: CortetsuDesign.spacingSection + root.navWidth
            screenState: root.screenState
            screen: root.screen
        }
    }
}
