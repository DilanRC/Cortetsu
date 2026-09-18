pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../services"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

// Network is intentionally a work surface: choose an item on the left and
// inspect or mutate it on the right. Repeated status cards made the old page
// long without adding information.
Item {
    id: root

    required property var screenState
    required property var screen
    property bool showingProfiles: false
    property int selectedIndex: 0

    readonly property var networks: CortetsuSettingsNetwork.networks
    readonly property var profiles: CortetsuSettingsNetwork.profiles.filter(profile => profile.type === "802-11-wireless")
    readonly property var selectedNetwork: networks[selectedIndex] ?? null
    readonly property var selectedProfile: profiles[selectedIndex] ?? null

    // This page is content-sized so the settings scroller does not enter a
    // polish loop by deriving its implicit height from its parent.
    implicitHeight: 560

    function selectFirst(): void {
        selectedIndex = 0;
    }

    onShowingProfilesChanged: selectFirst()
    Connections {
        target: CortetsuSettingsNetwork
        function onNetworksChanged(): void { if (root.selectedIndex >= root.networks.length) root.selectFirst(); }
        function onProfilesChanged(): void { if (root.selectedIndex >= root.profiles.length) root.selectFirst(); }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Red")
            detail: qsTr("Conexión, redes cercanas y perfiles guardados")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuText {
                Layout.fillWidth: true
                text: CortetsuSettingsNetwork.state === "error"
                    ? CortetsuSettingsNetwork.error
                    : CortetsuSettingsNetwork.operation.length > 0 && CortetsuSettingsNetwork.busy
                        ? qsTr("Actualizando %1…").arg(CortetsuSettingsNetwork.operation)
                        : CortetsuSettingsNetwork.activeSsid.length > 0
                            ? qsTr("Conectado a %1").arg(CortetsuSettingsNetwork.activeSsid)
                            : qsTr("Sin conexión Wi‑Fi activa")
                textSize: CortetsuTypography.bodySmallPx
                color: CortetsuSettingsNetwork.state === "error"
                    ? CortetsuDesign.colorWarning
                    : CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }

            CortetsuText {
                text: CortetsuSettingsNetwork.wifiEnabled
                    ? qsTr("Wi‑Fi activo")
                    : qsTr("Wi‑Fi apagado")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuToggle {
                checked: CortetsuSettingsNetwork.wifiEnabled
                disabled: CortetsuSettingsNetwork.busy
                onToggled: checked => CortetsuSettingsNetwork.setWifi(checked)
            }

            CortetsuButton {
                compact: true
                icon: "refresh"
                label: qsTr("Actualizar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: {
                    CortetsuSettingsNetwork.refreshNetworks();
                    CortetsuSettingsNetwork.refreshProfiles();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 420
            Layout.maximumHeight: 420
            spacing: CortetsuDesign.spacingSection

            CortetsuSurface {
                Layout.preferredWidth: Math.max(270, Math.min(360, parent.width * 0.38))
                Layout.fillHeight: true
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.42)
                outlined: true
                radiusValue: CortetsuDesign.radiusMedium

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            label: qsTr("Cercanas")
                            icon: "wifi"
                            active: !root.showingProfiles
                            onClicked: root.showingProfiles = false
                        }
                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            label: qsTr("Guardadas")
                            icon: "bookmark"
                            active: root.showingProfiles
                            onClicked: root.showingProfiles = true
                        }
                    }

                    ListView {
                        id: networkList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.showingProfiles ? root.profiles : root.networks
                        currentIndex: root.selectedIndex
                        onCurrentIndexChanged: if (currentIndex >= 0) root.selectedIndex = currentIndex

                        delegate: CortetsuListRow {
                            required property var modelData
                            required property int index
                            width: networkList.width
                            title: root.showingProfiles ? modelData.name : (modelData.ssid || qsTr("Red sin nombre"))
                            subtitle: root.showingProfiles
                                ? (modelData.autoconnect ? qsTr("Autoconexión activa") : qsTr("Autoconexión desactivada"))
                                : qsTr("Señal %1% · %2").arg(modelData.signal).arg(modelData.security || qsTr("Abierta"))
                            icon: root.showingProfiles ? "bookmark" : (modelData.active ? "wifi" : "wifi_find")
                            selected: index === root.selectedIndex
                            onClicked: root.selectedIndex = index
                        }

                        CortetsuStateMessage {
                            anchors.centerIn: parent
                            visible: networkList.count === 0
                            kind: CortetsuSettingsNetwork.busy ? "loading" : "empty"
                            title: CortetsuSettingsNetwork.busy ? qsTr("Buscando redes") : qsTr("No hay redes")
                            detail: root.showingProfiles
                                ? qsTr("Los perfiles guardados aparecerán aquí")
                                : qsTr("Pulsa Actualizar para volver a escanear")
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: CortetsuDesign.spacingSection

                    CortetsuSectionHeader {
                        Layout.fillWidth: true
                        title: root.showingProfiles
                            ? (root.selectedProfile?.name ?? qsTr("Perfil guardado"))
                            : (root.selectedNetwork?.ssid ?? qsTr("Selecciona una red"))
                        detail: root.showingProfiles
                            ? qsTr("Preferencias de conexión")
                            : root.selectedNetwork
                                ? qsTr("%1 · dispositivo %2").arg(root.selectedNetwork.security || qsTr("Red abierta")).arg(root.selectedNetwork.device)
                                : qsTr("Elige una red para ver sus acciones")
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: root.showingProfiles && !!root.selectedProfile
                        implicitHeight: 92
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.60)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusMedium

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            CortetsuIcon { text: "bookmark"; color: CortetsuDesign.colorPrimary; iconSize: CortetsuTypography.iconMediumPx }
                            ColumnLayout {
                                Layout.fillWidth: true
                                CortetsuText { text: qsTr("Autoconexión"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                                CortetsuText { text: root.selectedProfile?.autoconnect ? qsTr("Se conectará al iniciar sesión") : qsTr("Requiere conexión manual"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                            }
                            CortetsuToggle {
                                checked: root.selectedProfile?.autoconnect ?? false
                                onToggled: checked => CortetsuSettingsNetwork.setAutoconnect(root.selectedProfile.name, checked)
                            }
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && !!root.selectedNetwork
                        implicitHeight: 112
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.60)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusMedium
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            CortetsuIcon { text: root.selectedNetwork?.active ? "wifi" : "wifi_find"; color: CortetsuDesign.colorPrimary; iconSize: CortetsuTypography.iconLargePx }
                            ColumnLayout {
                                Layout.fillWidth: true
                                CortetsuText { text: root.selectedNetwork?.active ? qsTr("Conectada") : qsTr("Disponible"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                                CortetsuText { text: root.selectedNetwork ? qsTr("Señal %1% · %2").arg(root.selectedNetwork.signal).arg(root.selectedNetwork.security || qsTr("red abierta")) : ""; textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.showingProfiles && !!root.selectedProfile
                        CortetsuButton {
                            Layout.fillWidth: true
                            icon: "link_off"
                            label: qsTr("Desconectar")
                            onClicked: CortetsuSettingsNetwork.disconnect(root.selectedProfile.name)
                        }
                        CortetsuButton {
                            Layout.fillWidth: true
                            icon: "delete_outline"
                            label: qsTr("Olvidar")
                            onClicked: CortetsuSettingsNetwork.forget(root.selectedProfile.name)
                        }
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        visible: CortetsuSettingsNetwork.state === "error" || CortetsuSettingsNetwork.lastMessage.length > 0
                        text: CortetsuSettingsNetwork.state === "error" ? CortetsuSettingsNetwork.error : CortetsuSettingsNetwork.lastMessage
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuSettingsNetwork.state === "error" ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
