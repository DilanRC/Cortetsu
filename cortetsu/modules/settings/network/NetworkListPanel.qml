pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../../components"
import "../../../services"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var page

    height: implicitHeight
    implicitHeight: 520

    CortetsuSurface {
        anchors.fill: parent
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.60)
        outlined: true
        radiusValue: CortetsuDesign.radiusMedium
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingCompact
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuButton {
                Layout.fillWidth: true
                compact: true
                icon: "wifi"
                label: qsTr("Cercanas")
                active: !root.page.showingProfiles
                onClicked: root.page.showingProfiles = false
            }

            CortetsuButton {
                Layout.fillWidth: true
                compact: true
                icon: "bookmark"
                label: qsTr("Guardadas")
                active: root.page.showingProfiles
                onClicked: root.page.showingProfiles = true
            }
        }

        RowLayout {
            Layout.fillWidth: true

            CortetsuText {
                Layout.fillWidth: true
                text: root.page.showingProfiles
                    ? qsTr("%1 perfiles guardados").arg(root.page.profiles.length)
                    : qsTr("%1 redes visibles").arg(root.page.filteredNetworks.length)
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuButton {
                compact: true
                visible: !root.page.showingProfiles
                icon: root.page.strongestFirst ? "sort" : "sort_by_alpha"
                label: root.page.strongestFirst ? qsTr("Señal") : qsTr("Nombre")
                tooltipText: qsTr("Cambiar orden de la lista")
                onClicked: root.page.strongestFirst = !root.page.strongestFirst
            }
        }

        CortetsuSearchBar {
            Layout.fillWidth: true
            compact: true
            visible: !root.page.showingProfiles
            placeholderText: qsTr("Filtrar redes…")
            onTextChanged: root.page.networkQuery = text
        }

        ListView {
            id: networkList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: root.page.showingProfiles ? root.page.profiles : root.page.filteredNetworks
            currentIndex: root.page.selectedIndex
            onCurrentIndexChanged: if (currentIndex >= 0) root.page.selectedIndex = currentIndex

            delegate: Item {
                id: networkDelegate
                required property var modelData
                required property int index
                width: networkList.width
                height: 60

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: index === root.page.selectedIndex
                        ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.86)
                        : delegateMouse.containsMouse
                            ? Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.94)
                            : "transparent"
                    outlineColor: index === root.page.selectedIndex
                        ? Qt.alpha(CortetsuDesign.colorPrimary, 0.44)
                        : "transparent"
                    outlined: index === root.page.selectedIndex
                    radiusValue: CortetsuDesign.radiusSmall
                    hovered: delegateMouse.containsMouse
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: 30
                    radius: 1
                    visible: index === root.page.selectedIndex
                    color: CortetsuDesign.colorWashi
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: CortetsuDesign.spacingStandard
                    anchors.rightMargin: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuIcon {
                        text: root.page.showingProfiles
                            ? "bookmark"
                            : root.page.networkIsActive(networkDelegate.modelData)
                                ? "wifi"
                                : networkDelegate.modelData.security !== WifiSecurityType.Open
                                    ? "wifi_lock"
                                    : "wifi_find"
                        color: root.page.networkIsActive(networkDelegate.modelData)
                            ? CortetsuDesign.colorSuccess
                            : index === root.page.selectedIndex
                                ? CortetsuDesign.colorOnPrimaryContainer
                                : CortetsuDesign.colorPrimary
                        iconSize: CortetsuTypography.iconMediumPx
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.page.showingProfiles
                                ? networkDelegate.modelData.name
                                : (networkDelegate.modelData.name || qsTr("Red sin nombre"))
                            textSize: CortetsuTypography.bodySmallPx
                            font.weight: root.page.networkIsActive(networkDelegate.modelData) ? Font.DemiBold : Font.Normal
                            color: index === root.page.selectedIndex
                                ? CortetsuDesign.colorOnPrimaryContainer
                                : CortetsuDesign.colorOnSurface
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.page.showingProfiles
                                ? (networkDelegate.modelData.autoconnect
                                    ? qsTr("Autoconexión activa")
                                    : qsTr("Autoconexión desactivada"))
                                : qsTr("%1 · %2")
                                    .arg(root.page.signalLabel(root.page.networkSignal(networkDelegate.modelData)))
                                    .arg(root.page.securityLabel(networkDelegate.modelData))
                            textSize: CortetsuTypography.labelSmallPx
                            color: index === root.page.selectedIndex
                                ? Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.76)
                                : CortetsuDesign.colorOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    SignalBars {
                        visible: !root.page.showingProfiles
                        signalValue: Math.max(0, root.page.networkSignal(networkDelegate.modelData))
                        activeColor: root.page.networkIsActive(networkDelegate.modelData)
                            ? CortetsuDesign.colorSuccess
                            : index === root.page.selectedIndex
                                ? CortetsuDesign.colorOnPrimaryContainer
                                : CortetsuDesign.colorPrimary
                    }

                    CortetsuIcon {
                        visible: !root.page.showingProfiles && root.page.networkIsActive(networkDelegate.modelData)
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
                    onClicked: root.page.selectedIndex = networkDelegate.index
                }
            }

            CortetsuStateMessage {
                anchors.centerIn: parent
                visible: networkList.count === 0
                kind: CortetsuSettingsNetwork.busy ? "loading" : "empty"
                title: CortetsuSettingsNetwork.busy
                    ? qsTr("Buscando redes")
                    : root.page.showingProfiles
                        ? qsTr("No hay perfiles guardados")
                        : root.page.networkQuery.length > 0
                            ? qsTr("No hay coincidencias")
                            : qsTr("No hay redes visibles")
                detail: root.page.showingProfiles
                    ? qsTr("Los perfiles aparecerán después de conectarte a una red")
                    : qsTr("Pulsa Actualizar para volver a escanear")
            }
        }
    }
}
