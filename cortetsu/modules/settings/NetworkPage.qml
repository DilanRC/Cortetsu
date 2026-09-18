pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components"
import "../../services"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

// Wi-Fi is a work surface, not a status card. The page deliberately follows
// the real task order: understand the current link, find a network, inspect
// its properties, then perform one supported NetworkManager action.
Item {
    id: root

    required property var screenState
    required property var screen

    property bool showingProfiles: false
    property int selectedIndex: 0
    property string networkQuery: ""
    property bool strongestFirst: true
    property bool passwordVisible: false
    property string password: ""

    readonly property var networks: CortetsuSettingsNetwork.networks
    readonly property var profiles: CortetsuSettingsNetwork.profiles.filter(profile => profile.type === "802-11-wireless")
    readonly property var filteredNetworks: {
        const query = root.networkQuery.trim().toLowerCase();
        const matching = root.networks.filter(network =>
            !query || String(network.ssid ?? "").toLowerCase().includes(query));
        return matching.slice().sort((left, right) => {
            if (left.active !== right.active)
                return left.active ? -1 : 1;
            return root.strongestFirst
                ? Number(right.signal ?? 0) - Number(left.signal ?? 0)
                : String(left.ssid ?? "").localeCompare(String(right.ssid ?? ""));
        });
    }
    readonly property var selectedNetwork: root.filteredNetworks[root.selectedIndex] ?? null
    readonly property var selectedProfile: root.profiles[root.selectedIndex] ?? null
    readonly property var activeNetwork: root.networks.find(network => network.active) ?? null
    readonly property bool selectedIsActive: !!root.selectedNetwork?.active
    readonly property bool selectedNeedsPassword: !!root.selectedNetwork
        && String(root.selectedNetwork.security ?? "").length > 0
        && !root.selectedIsActive

    // Fixed and explicit: Content.qml gives this page a known viewport so the
    // settings Flickable never derives its height from its own parent.
    implicitHeight: 760

    function signalLabel(signal): string {
        const value = Number(signal ?? -1);
        if (value < 0) return qsTr("Sin medición");
        if (value >= 80) return qsTr("Excelente");
        if (value >= 60) return qsTr("Buena");
        if (value >= 35) return qsTr("Aceptable");
        return qsTr("Débil");
    }

    function signalValue(signal): real {
        return Math.max(0, Math.min(100, Number(signal ?? 0))) / 100;
    }

    function securityLabel(network): string {
        if (!network || String(network.security ?? "").length === 0)
            return qsTr("Red abierta");
        return String(network.security);
    }

    function resetSelection(): void {
        selectedIndex = 0;
        password = "";
        passwordVisible = false;
    }

    function refreshAll(): void {
        CortetsuSettingsNetwork.refreshNetworks();
        CortetsuSettingsNetwork.refreshProfiles();
    }

    function connectSelected(): void {
        if (!root.selectedNetwork)
            return;
        CortetsuSettingsNetwork.connect(root.selectedNetwork.ssid, root.passwordVisible ? root.password : "");
        root.password = "";
    }

    onShowingProfilesChanged: resetSelection()
    onNetworkQueryChanged: resetSelection()

    Connections {
        target: CortetsuSettingsNetwork
        function onNetworksChanged(): void {
            if (root.selectedIndex >= root.filteredNetworks.length)
                root.resetSelection();
        }
        function onProfilesChanged(): void {
            if (root.selectedIndex >= root.profiles.length)
                root.resetSelection();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Red")
                detail: qsTr("Conexiones inalámbricas y perfiles de NetworkManager")
            }

            CortetsuButton {
                compact: true
                icon: "refresh"
                label: qsTr("Actualizar")
                tooltipText: qsTr("Buscar redes y volver a leer perfiles")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.refreshAll()
            }
        }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 56
            baseColor: CortetsuSettingsNetwork.state === "error"
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.12)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.54)
            outlineColor: CortetsuSettingsNetwork.state === "error"
                ? Qt.alpha(CortetsuDesign.colorWarning, 0.54)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
            outlined: true
            radiusValue: CortetsuDesign.radiusMedium

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.rightMargin: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: CortetsuSettingsNetwork.state === "error" ? "warning" : "wifi"
                    color: CortetsuSettingsNetwork.state === "error"
                        ? CortetsuDesign.colorWarning
                        : CortetsuDesign.colorPrimary
                    iconSize: CortetsuTypography.iconMediumPx
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: CortetsuSettingsNetwork.state === "error"
                        ? CortetsuSettingsNetwork.error
                        : CortetsuSettingsNetwork.busy
                            ? qsTr("Actualizando %1…").arg(CortetsuSettingsNetwork.operation)
                            : CortetsuSettingsNetwork.activeSsid.length > 0
                                ? qsTr("Conectado a %1").arg(CortetsuSettingsNetwork.activeSsid)
                                : qsTr("No hay una conexión Wi‑Fi activa")
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuSettingsNetwork.state === "error"
                        ? CortetsuDesign.colorWarning
                        : CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }

                CortetsuText {
                    text: CortetsuSettingsNetwork.wifiEnabled ? qsTr("Wi‑Fi activado") : qsTr("Wi‑Fi apagado")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }

                CortetsuToggle {
                    checked: CortetsuSettingsNetwork.wifiEnabled
                    disabled: CortetsuSettingsNetwork.busy
                    onToggled: checked => CortetsuSettingsNetwork.setWifi(checked)
                }
            }
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: !!root.activeNetwork
            implicitHeight: 118
            baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.50)
            outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.44)
            outlined: true
            radiusValue: CortetsuDesign.radiusMedium

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuSurface {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    baseColor: Qt.alpha(CortetsuDesign.colorSuccess, 0.16)
                    outlineColor: Qt.alpha(CortetsuDesign.colorSuccess, 0.32)
                    outlined: true
                    radiusValue: CortetsuDesign.radiusMedium
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "wifi"
                        color: CortetsuDesign.colorSuccess
                        iconSize: CortetsuTypography.iconLargePx
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    CortetsuText { text: qsTr("Conexión actual"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                    CortetsuText { text: root.activeNetwork?.ssid ?? CortetsuSettingsNetwork.activeSsid; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    CortetsuText {
                        text: root.activeNetwork
                            ? qsTr("%1% · %2 · %3").arg(root.activeNetwork.signal).arg(root.signalLabel(root.activeNetwork.signal)).arg(root.securityLabel(root.activeNetwork))
                            : qsTr("NetworkManager gestiona esta conexión")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 220
                    spacing: CortetsuDesign.spacingCompact
                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText { Layout.fillWidth: true; text: qsTr("Calidad de señal"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                        CortetsuText { text: root.activeNetwork ? qsTr("%1%").arg(root.activeNetwork.signal) : "—"; textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                    }
                    CortetsuProgressBar { Layout.fillWidth: true; value: root.signalValue(root.activeNetwork?.signal); fillColor: CortetsuDesign.colorSuccess; barHeight: 6 }
                    CortetsuText { Layout.fillWidth: true; text: root.activeNetwork?.device ?? qsTr("Dispositivo no disponible"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 430
            spacing: CortetsuDesign.spacingSection

            CortetsuSurface {
                Layout.preferredWidth: Math.max(330, Math.min(420, parent.width * 0.40))
                Layout.fillHeight: true
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.44)
                outlined: true
                radiusValue: CortetsuDesign.radiusMedium

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuButton { Layout.fillWidth: true; compact: true; label: qsTr("Cercanas"); icon: "wifi"; active: !root.showingProfiles; onClicked: root.showingProfiles = false }
                        CortetsuButton { Layout.fillWidth: true; compact: true; label: qsTr("Guardadas"); icon: "bookmark"; active: root.showingProfiles; onClicked: root.showingProfiles = true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.showingProfiles ? qsTr("%1 perfiles conocidos").arg(root.profiles.length) : qsTr("%1 redes visibles").arg(root.filteredNetworks.length)
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuButton {
                            compact: true
                            icon: root.strongestFirst ? "sort" : "sort_by_alpha"
                            label: root.strongestFirst ? qsTr("Señal") : qsTr("Nombre")
                            tooltipText: qsTr("Cambiar orden de la lista")
                            visible: !root.showingProfiles
                            onClicked: root.strongestFirst = !root.strongestFirst
                        }
                    }

                    CortetsuSearchBar {
                        Layout.fillWidth: true
                        compact: true
                        visible: !root.showingProfiles
                        placeholderText: qsTr("Filtrar redes")
                        onTextChanged: root.networkQuery = text
                    }

                    ListView {
                        id: networkList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.showingProfiles ? root.profiles : root.filteredNetworks
                        currentIndex: root.selectedIndex
                        onCurrentIndexChanged: if (currentIndex >= 0) root.selectedIndex = currentIndex

                        delegate: Item {
                            id: networkDelegate
                            required property var modelData
                            required property int index
                            width: networkList.width
                            height: 64

                            CortetsuSurface {
                                anchors.fill: parent
                                baseColor: index === root.selectedIndex
                                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.82)
                                    : delegateMouse.containsMouse ? Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.94) : "transparent"
                                outlineColor: index === root.selectedIndex ? Qt.alpha(CortetsuDesign.colorPrimary, 0.38) : "transparent"
                                outlined: index === root.selectedIndex
                                radiusValue: CortetsuDesign.radiusSmall
                                hovered: delegateMouse.containsMouse
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: CortetsuDesign.spacingCompact
                                anchors.rightMargin: CortetsuDesign.spacingCompact
                                spacing: CortetsuDesign.spacingCompact

                                CortetsuIcon {
                                    text: root.showingProfiles ? "bookmark" : networkDelegate.modelData.active ? "wifi" : networkDelegate.modelData.security ? "wifi_lock" : "wifi_find"
                                    color: networkDelegate.modelData.active ? CortetsuDesign.colorSuccess : index === root.selectedIndex ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorPrimary
                                    iconSize: CortetsuTypography.iconMediumPx
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: root.showingProfiles ? networkDelegate.modelData.name : (networkDelegate.modelData.ssid || qsTr("Red sin nombre"))
                                        textSize: CortetsuTypography.bodySmallPx
                                        font.weight: networkDelegate.modelData.active ? Font.DemiBold : Font.Normal
                                        color: index === root.selectedIndex ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
                                        elide: Text.ElideRight
                                    }
                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: root.showingProfiles
                                            ? (networkDelegate.modelData.autoconnect ? qsTr("Autoconexión activa") : qsTr("Autoconexión desactivada"))
                                            : qsTr("%1 · %2").arg(root.signalLabel(networkDelegate.modelData.signal)).arg(root.securityLabel(networkDelegate.modelData))
                                        textSize: CortetsuTypography.labelSmallPx
                                        color: index === root.selectedIndex ? Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.76) : CortetsuDesign.colorOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                Row {
                                    visible: !root.showingProfiles
                                    height: 24
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter
                                    Repeater {
                                        model: 4
                                        delegate: Rectangle {
                                            required property int index
                                            width: 4
                                            height: 8 + index * 4
                                            y: 24 - height
                                            radius: 2
                                            color: index < Math.ceil(Number(networkDelegate.modelData.signal ?? 0) / 25)
                                                ? (networkDelegate.modelData.active ? CortetsuDesign.colorSuccess : CortetsuDesign.colorPrimary)
                                                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.42)
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: delegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedIndex = networkDelegate.index
                            }
                        }

                        CortetsuStateMessage {
                            anchors.centerIn: parent
                            visible: networkList.count === 0
                            kind: CortetsuSettingsNetwork.busy ? "loading" : "empty"
                            title: CortetsuSettingsNetwork.busy ? qsTr("Buscando redes") : root.networkQuery.length > 0 ? qsTr("No hay coincidencias") : root.showingProfiles ? qsTr("No hay perfiles guardados") : qsTr("No hay redes visibles")
                            detail: root.showingProfiles ? qsTr("Los perfiles aparecerán después de conectarte a una red") : qsTr("Prueba Actualizar para volver a escanear")
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuSectionHeader {
                        Layout.fillWidth: true
                        title: root.showingProfiles ? (root.selectedProfile?.name ?? qsTr("Perfil guardado")) : (root.selectedNetwork?.ssid ?? qsTr("Selecciona una red"))
                        detail: root.showingProfiles
                            ? qsTr("Preferencias de conexión guardadas")
                            : root.selectedNetwork
                                ? qsTr("%1 · %2").arg(root.securityLabel(root.selectedNetwork)).arg(root.selectedNetwork.device || qsTr("dispositivo no disponible"))
                                : qsTr("Elige una red para ver sus propiedades")
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && !!root.selectedNetwork
                        implicitHeight: 286
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.68)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusMedium

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingStandard

                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuSurface {
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 58
                                    baseColor: root.selectedIsActive ? Qt.alpha(CortetsuDesign.colorSuccess, 0.16) : Qt.alpha(CortetsuDesign.colorPrimary, 0.12)
                                    outlined: false
                                    radiusValue: CortetsuDesign.radiusMedium
                                    CortetsuIcon { anchors.centerIn: parent; text: root.selectedIsActive ? "wifi" : "wifi_find"; color: root.selectedIsActive ? CortetsuDesign.colorSuccess : CortetsuDesign.colorPrimary; iconSize: CortetsuTypography.iconLargePx }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    CortetsuText { text: root.selectedIsActive ? qsTr("Conectada ahora") : qsTr("Red disponible"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                    CortetsuText { text: root.selectedNetwork?.ssid ?? ""; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    CortetsuText { text: root.selectedNetwork ? root.signalLabel(root.selectedNetwork.signal) : ""; textSize: CortetsuTypography.bodySmallPx; color: root.selectedIsActive ? CortetsuDesign.colorSuccess : CortetsuDesign.colorOnSurfaceVariant }
                                }
                                CortetsuText { text: root.selectedNetwork ? qsTr("%1%").arg(root.selectedNetwork.signal) : "—"; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold }
                            }

                            CortetsuProgressBar { Layout.fillWidth: true; value: root.signalValue(root.selectedNetwork?.signal); fillColor: root.selectedIsActive ? CortetsuDesign.colorSuccess : CortetsuDesign.colorPrimary; barHeight: 7 }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: CortetsuDesign.spacingSection
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    CortetsuText { text: qsTr("Seguridad"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                    CortetsuText { text: root.securityLabel(root.selectedNetwork); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    CortetsuText { text: qsTr("Dispositivo"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                    CortetsuText { text: root.selectedNetwork?.device || qsTr("No disponible"); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: !root.selectedIsActive
                                CortetsuText { Layout.fillWidth: true; text: root.selectedNeedsPassword ? qsTr("Esta red requiere contraseña") : qsTr("Red abierta: puedes conectarte directamente"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant; wrapMode: Text.WordWrap }
                                CortetsuButton { compact: true; label: qsTr("Conectar"); icon: "wifi"; disabled: CortetsuSettingsNetwork.busy || (root.selectedNeedsPassword && root.password.length === 0); onClicked: root.connectSelected() }
                            }

                            TextField {
                                Layout.fillWidth: true
                                visible: root.selectedNeedsPassword
                                placeholderText: qsTr("Contraseña de Wi‑Fi")
                                echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
                                text: root.password
                                onTextChanged: root.password = text
                                color: CortetsuDesign.colorOnSurface
                                placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
                                leftPadding: CortetsuDesign.spacingStandard
                                rightPadding: CortetsuDesign.spacingStandard
                                implicitHeight: 42
                                background: CortetsuSurface { radiusValue: CortetsuDesign.radiusSmall; baseColor: CortetsuDesign.colorSurfaceGlassStrong; outlined: true }
                            }

                            CortetsuButton {
                                Layout.fillWidth: true
                                visible: root.selectedNeedsPassword
                                compact: true
                                label: root.passwordVisible ? qsTr("Ocultar contraseña") : qsTr("Mostrar contraseña")
                                icon: root.passwordVisible ? "visibility_off" : "visibility"
                                onClicked: root.passwordVisible = !root.passwordVisible
                            }
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: root.showingProfiles && !!root.selectedProfile
                        implicitHeight: 196
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.68)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusMedium

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingCompact
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuSurface {
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 52
                                    baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                                    outlined: false
                                    radiusValue: CortetsuDesign.radiusMedium
                                    CortetsuIcon { anchors.centerIn: parent; text: "bookmark"; color: CortetsuDesign.colorPrimary; iconSize: CortetsuTypography.iconMediumPx }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    CortetsuText { text: qsTr("Perfil de NetworkManager"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                    CortetsuText { text: root.selectedProfile?.name ?? ""; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText { Layout.fillWidth: true; text: root.selectedProfile?.autoconnect ? qsTr("Se conectará automáticamente al iniciar sesión") : qsTr("La conexión automática está desactivada"); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant; wrapMode: Text.WordWrap }
                                CortetsuToggle { checked: root.selectedProfile?.autoconnect ?? false; disabled: CortetsuSettingsNetwork.busy; onToggled: checked => CortetsuSettingsNetwork.setAutoconnect(root.selectedProfile.name, checked) }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuButton { Layout.fillWidth: true; compact: true; icon: "link_off"; label: qsTr("Desconectar"); disabled: CortetsuSettingsNetwork.busy; onClicked: CortetsuSettingsNetwork.disconnect(root.selectedProfile.name) }
                                CortetsuButton { Layout.fillWidth: true; compact: true; icon: "delete_outline"; label: qsTr("Olvidar perfil"); danger: true; disabled: CortetsuSettingsNetwork.busy; onClicked: CortetsuSettingsNetwork.forget(root.selectedProfile.name) }
                            }
                        }
                    }

                    CortetsuStateMessage {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.showingProfiles && !root.selectedNetwork
                        kind: "empty"
                        title: qsTr("Selecciona una red")
                        detail: qsTr("Elige una red de la lista para consultar su señal, seguridad y acciones disponibles")
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        visible: CortetsuSettingsNetwork.lastMessage.length > 0
                        text: CortetsuSettingsNetwork.lastMessage
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorSuccess
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
