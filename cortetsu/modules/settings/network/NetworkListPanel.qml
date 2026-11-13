pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../../components"
import "../../../services"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// Nearby networks or saved profiles. The list is as tall as its rows up to
// `maxRows`, then it scrolls: one network takes one row, not a panel.
ColumnLayout {
    id: root

    required property var page
    readonly property int rowHeight: 56
    readonly property int maxRows: 7

    Layout.fillWidth: true
    spacing: CortetsuDesign.spacingCompact

    CortetsuTabBar {
        objectName: "networkTabs"
        Layout.fillWidth: true
        accessibleName: qsTr("Redes Wi-Fi")
        model: [{ label: qsTr("Cercanas"), icon: "wifi" }, { label: qsTr("Guardadas"), icon: "bookmark" }]
        currentIndex: root.page.showingProfiles ? 1 : 0
        onSelected: index => root.page.showingProfiles = index === 1
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: CortetsuDesign.spacingCompact
        spacing: CortetsuDesign.spacingCompact

        CortetsuText {
            Layout.fillWidth: true
            text: root.page.showingProfiles
                ? qsTr("%1 perfiles guardados").arg(root.page.profiles.length)
                : !CortetsuSettingsNetwork.wifiEnabled
                    ? qsTr("Enciende el Wi-Fi para buscar redes")
                    : qsTr("%1 a la vista").arg(root.page.filteredNetworks.length)
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }

        CortetsuButton {
            compact: true
            visible: !root.page.showingProfiles && root.page.networks.length > 1
            icon: root.page.strongestFirst ? "sort" : "sort_by_alpha"
            label: root.page.strongestFirst ? qsTr("Señal") : qsTr("Nombre")
            tooltipText: qsTr("Cambiar orden de la lista")
            onClicked: root.page.strongestFirst = !root.page.strongestFirst
        }

        CortetsuButton {
            objectName: "wifiScan"
            compact: true
            visible: !root.page.showingProfiles
            icon: "refresh"
            label: qsTr("Actualizar")
            tooltipText: qsTr("Buscar redes de nuevo")
            disabled: CortetsuSettingsNetwork.busy || !CortetsuSettingsNetwork.wifiEnabled
            onClicked: root.page.refreshAll()
        }
    }

    // A filter earns its row only when there is a list to shorten.
    CortetsuSearchBar {
        objectName: "networkFilter"
        Layout.fillWidth: true
        compact: true
        visible: !root.page.showingProfiles && (root.page.networks.length > root.maxRows || text.length > 0)
        placeholderText: qsTr("Filtrar redes…")
        onTextChanged: root.page.networkQuery = text
    }

    ListView {
        id: networkList
        objectName: "networkList"
        Layout.fillWidth: true
        Layout.preferredHeight: count > 0
            ? Math.min(count, root.maxRows) * root.rowHeight
            : emptyState.implicitHeight + CortetsuDesign.spacingSpacious * 2
        clip: true
        interactive: count > root.maxRows
        // Arrow keys follow `interactive` unless told otherwise, and a list
        // short enough not to scroll still has to move its selection.
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.page.showingProfiles ? root.page.profiles : root.page.filteredNetworks
        currentIndex: root.page.selectedIndex
        onCurrentIndexChanged: if (currentIndex >= 0) root.page.selectedIndex = currentIndex
        // One Tab stop; Up and Down move the selection inside it.
        activeFocusOnTab: count > 0
        Accessible.role: Accessible.List
        Accessible.name: root.page.showingProfiles ? qsTr("Redes guardadas") : qsTr("Redes cercanas")

        Rectangle {
            anchors.fill: parent
            z: 2
            visible: networkList.activeFocus
            color: "transparent"
            radius: CortetsuDesign.radiusMedium
            border.width: 2
            border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.82)
        }

        delegate: Item {
            id: networkDelegate
            required property var modelData
            required property int index
            readonly property bool selected: index === root.page.selectedIndex
            readonly property bool active: root.page.networkIsActive(modelData)
            readonly property color ink: selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
            width: networkList.width
            height: root.rowHeight

            // Open rows: a ground only under the pointer or the selection.
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1
                radius: CortetsuDesign.radiusMedium
                color: networkDelegate.selected
                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.86)
                    : Qt.alpha(CortetsuDesign.colorOnSurface, delegateMouse.containsMouse ? 0.06 : 0)
                border.width: networkDelegate.selected ? CortetsuDesign.outlineWidth : 0
                border.color: Qt.alpha(CortetsuDesign.colorIndicator, 0.5)
            }

            CortetsuDivider {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.rightMargin: CortetsuDesign.spacingStandard
                // Neither over the first row nor against a selected one.
                visible: networkDelegate.index > 0 && !networkDelegate.selected
                    && networkDelegate.index - 1 !== root.page.selectedIndex
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.rightMargin: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: root.page.showingProfiles
                        ? "bookmark"
                        : networkDelegate.active
                            ? "wifi"
                            : networkDelegate.modelData.security !== WifiSecurityType.Open ? "wifi_lock" : "wifi_find"
                    color: networkDelegate.active
                        ? CortetsuDesign.colorSuccess
                        : networkDelegate.selected ? networkDelegate.ink : CortetsuDesign.colorIndicator
                    iconSize: CortetsuTypography.iconMediumPx
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    CortetsuText {
                        Layout.fillWidth: true
                        text: networkDelegate.modelData.name || qsTr("Red sin nombre")
                        textSize: CortetsuTypography.bodyPx
                        font.weight: networkDelegate.active ? Font.DemiBold : Font.Normal
                        color: networkDelegate.ink
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.page.showingProfiles
                            ? (networkDelegate.modelData.autoconnect
                                ? qsTr("Conexión automática")
                                : qsTr("Sin conexión automática"))
                            : networkDelegate.active
                                ? qsTr("Conectada · %1").arg(root.page.securityLabel(networkDelegate.modelData))
                                : root.page.securityLabel(networkDelegate.modelData)
                        textSize: CortetsuTypography.labelSmallPx
                        color: networkDelegate.selected ? networkDelegate.ink : CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                SignalBars {
                    visible: !root.page.showingProfiles
                    signalValue: Math.max(0, root.page.networkSignal(networkDelegate.modelData))
                    activeColor: networkDelegate.active
                        ? CortetsuDesign.colorSuccess
                        : networkDelegate.selected ? networkDelegate.ink : CortetsuDesign.colorIndicator
                }

                CortetsuIcon {
                    visible: !root.page.showingProfiles && networkDelegate.active
                    text: "check"
                    color: CortetsuDesign.colorSuccess
                    iconSize: CortetsuTypography.iconSmallPx
                }
            }

            MouseArea {
                id: delegateMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    networkList.forceActiveFocus();
                    root.page.selectedIndex = networkDelegate.index;
                }
            }
        }

        CortetsuStateMessage {
            id: emptyState
            objectName: "networkListState"
            anchors.centerIn: parent
            visible: networkList.count === 0
            kind: CortetsuSettingsNetwork.busy ? "loading" : "empty"
            icon: CortetsuSettingsNetwork.busy ? "sync" : !CortetsuSettingsNetwork.wifiEnabled && !root.page.showingProfiles ? "wifi_off" : "inbox"
            width: Math.max(0, networkList.width - CortetsuDesign.spacingSection * 2)
            title: CortetsuSettingsNetwork.busy
                ? qsTr("Buscando redes")
                : root.page.showingProfiles
                    ? qsTr("No hay perfiles guardados")
                    : !CortetsuSettingsNetwork.wifiEnabled
                        ? qsTr("El Wi-Fi está apagado")
                        : root.page.networkQuery.length > 0
                            ? qsTr("No hay coincidencias")
                            : qsTr("No hay redes visibles")
            detail: root.page.showingProfiles
                ? qsTr("Los perfiles aparecerán después de conectarte a una red")
                : !CortetsuSettingsNetwork.wifiEnabled
                    ? qsTr("Enciéndelo arriba para ver las redes cercanas")
                    : qsTr("Pulsa Actualizar para volver a escanear")
        }
    }
}
