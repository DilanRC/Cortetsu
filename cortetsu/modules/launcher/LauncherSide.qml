pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "services"

// The launcher's side column while browsing: the commands the search box
// understands, and what was launched lately. Both read real state; neither
// is a Tab stop, so Tab and the arrows keep moving through the results.
ColumnLayout {
    id: root

    required property var screenState
    // Puts text in the search box and gives it the keys back.
    signal query(string text)
    signal openSurface(string name)

    readonly property var recent: {
        const all = Apps.entries();
        return Apps.recentIds.map(id => all.find(entry => entry.id === id)).filter(entry => !!entry).slice(0, 4);
    }

    spacing: CortetsuDesign.spacingCompact

    component SideCard: Item {
        id: card
        property string icon
        property string title
        default property alias content: rows.data
        Layout.fillWidth: true
        implicitHeight: column.implicitHeight + CortetsuDesign.spacingStandard * 2

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: Qt.alpha(CortetsuDesign.colorWashi, 0.035)
            outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.10)
        }
        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact
            RowLayout {
                spacing: CortetsuDesign.spacingCompact
                CortetsuIcon {
                    text: card.icon
                    iconSize: CortetsuTypography.iconSmallPx
                    color: CortetsuDesign.colorPrimary
                }
                CortetsuText {
                    text: card.title
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                }
            }
            ColumnLayout {
                id: rows
                Layout.fillWidth: true
                spacing: 2
            }
        }
    }

    SideCard {
        objectName: "launcherCommands"
        icon: "bolt"
        title: qsTr("Comandos rápidos")

        Repeater {
            model: [
                { icon: "terminal", title: qsTr("Comandos"), subtitle: qsTr("Capturas, fondos, superficies…"), text: CortetsuConfig.actionPrefix },
                { icon: "calculate", title: qsTr("Calculadora"), subtitle: qsTr("Ej. «%1calc 2^10»").arg(CortetsuConfig.actionPrefix), text: `${CortetsuConfig.actionPrefix}calc ` },
                { icon: "folder_open", title: qsTr("Buscar archivos"), subtitle: qsTr("En tu carpeta personal"), text: `${CortetsuConfig.actionPrefix}files ` },
                { icon: "settings", title: qsTr("Ajustes"), subtitle: qsTr("Cortetsu y el sistema"), opensSettings: true }
            ]
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                activeFocusOnTab: false
                icon: modelData.icon
                title: modelData.title
                subtitle: modelData.subtitle
                onClicked: modelData.opensSettings ? root.openSurface("settings") : root.query(modelData.text)
            }
        }
    }

    SideCard {
        objectName: "launcherRecent"
        visible: root.recent.length > 0
        icon: "history"
        title: qsTr("Recientes")

        Repeater {
            model: root.recent
            delegate: Item {
                id: row
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Abrir %1").arg(row.modelData?.name ?? "")
                Accessible.onPressAction: row.launch()
                function launch(): void {
                    Apps.launch(row.modelData);
                    root.screenState.launcher = false;
                }

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusSmall
                    baseColor: "transparent"
                    hoverColor: Qt.alpha(CortetsuDesign.colorWashi, 0.06)
                    hovered: mouse.containsMouse
                    pressed: mouse.pressed
                    outlined: false
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: CortetsuDesign.spacingCompact
                    anchors.rightMargin: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact
                    IconImage {
                        implicitSize: 24
                        source: Quickshell.iconPath(row.modelData?.icon, "image-missing")
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: row.modelData?.name ?? ""
                        textSize: CortetsuTypography.bodySmallPx
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.launch()
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
