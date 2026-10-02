pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../../components"
import "../../services"
import "../CortetsuDesign.js" as Design
import "../CortetsuTypography.js" as Typography

Item {
    id: root
    required property var screenState
    required property var screen
    readonly property var wifi: Connectivity.wifi
    property var selectedNetwork: null
    property string selectedUuid: ""
    property string confirmForgetUuid: ""
    property bool showingProfiles: false
    property bool showVpn: true
    readonly property var selectedDetails: selectedNetwork?.connected ? wifi.details[selectedNetwork.device.name] ?? ({}) : ({})
    readonly property string scanOwner: "settings-wifi-" + String(root)
    readonly property var selectedProfile: wifi.profiles.find(profile => profile.uuid === selectedUuid) ?? null
    readonly property var sortedNetworks: wifi.networks.slice().sort((a, b) =>
        Number(b.connected) - Number(a.connected) || Number(b.known) - Number(a.known)
        || b.signalStrength - a.signalStrength)
    implicitHeight: body.implicitHeight

    function refreshAll(): void { wifi.refresh(); }
    function selectNetwork(network): void {
        selectedNetwork = network;
        selectedUuid = "";
        confirmForgetUuid = "";
        password.clear();
        if (network?.device) wifi.refreshDetails(network.device.name);
    }
    function connectSelected(): void {
        if (!selectedNetwork) return;
        const profile = selectedProfile?.ssid === selectedNetwork.name
            && (!selectedProfile.interface || selectedProfile.interface === selectedNetwork.device.name) ? selectedProfile : null;
        wifi.connectNetwork(selectedNetwork, password.text, profile);
        password.clear();
    }
    function networkState(network): string {
        const op = wifi.operation;
        if (wifi.operationNetwork === network && ["connecting", "auth-required", "failed"].includes(op.state))
            return op.state === "failed" ? op.lastError : op.state === "auth-required"
                ? qsTr("Se requieren credenciales") : qsTr("Conectando…");
        return network.connected ? Connectivity.internetLabel
            : network.known ? qsTr("Guardada") : qsTr("Disponible");
    }
    onVisibleChanged: {
        wifi.setScanOwner(scanOwner, visible);
        if (!visible) password.clear();
    }
    Component.onCompleted: wifi.setScanOwner(scanOwner, visible)
    Component.onDestruction: wifi.setScanOwner(scanOwner, false)
    Connections {
        target: root.wifi
        function onNetworksChanged(): void {
            if (root.selectedNetwork && !root.wifi.networks.includes(root.selectedNetwork))
                root.selectNetwork(null);
        }
    }

    ColumnLayout {
        id: body
        width: parent.width
        spacing: Design.spacingStandard
        RowLayout {
            Layout.fillWidth: true
            CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Wi-Fi"); detail: Connectivity.internetLabel }
            CortetsuToggle {
                checked: root.wifi.wifiEnabled
                disabled: !root.wifi.wifiDevice || !root.wifi.hardwareEnabled
                onToggled: value => root.wifi.setEnabled(value)
                Accessible.name: qsTr("Activar Wi-Fi")
            }
        }
        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: !root.wifi.wifiDevice || !root.wifi.wifiEnabled || !root.wifi.hardwareEnabled
            title: !root.wifi.wifiDevice ? qsTr("Wi-Fi no disponible")
                : !root.wifi.hardwareEnabled ? qsTr("Radio bloqueada") : qsTr("Wi-Fi desactivado")
            detail: !root.wifi.wifiDevice ? qsTr("Comprueba el adaptador y NetworkManager")
                : !root.wifi.hardwareEnabled ? qsTr("Comprueba rfkill o el interruptor del equipo") : ""
        }
        CortetsuSurface {
            Layout.fillWidth: true
            visible: !!root.wifi.activeNetwork
            implicitHeight: activeBody.implicitHeight + Design.spacingComfortable * 2
            baseColor: Qt.alpha(Design.colorPrimaryContainer, 0.32)
            outlined: true
            radiusValue: Design.radiusLarge
            ColumnLayout {
                id: activeBody
                anchors.fill: parent
                anchors.margins: Design.spacingComfortable
                spacing: Design.spacingCompact
                CortetsuText { text: qsTr("Conectada"); textSize: Design.labelSmallPx; color: Design.colorOnSurfaceVariant }
                CortetsuText { text: root.wifi.activeNetwork?.name ?? ""; textSize: Typography.titleLargePx; font.weight: Font.DemiBold }
                CortetsuText {
                    text: qsTr("%1% de señal · %2").arg(Math.round((root.wifi.activeNetwork?.signalStrength ?? 0) * 100)).arg(Connectivity.internetLabel)
                    textSize: Design.bodySmallPx
                }
                RowLayout {
                    CortetsuButton { label: qsTr("Propiedades"); icon: "info"; onClicked: root.selectNetwork(root.wifi.activeNetwork) }
                    CortetsuButton { label: qsTr("Desconectar"); icon: "link_off"; onClicked: root.wifi.disconnectNetwork(root.wifi.activeNetwork) }
                }
            }
        }
        CortetsuText {
            Layout.fillWidth: true
            visible: ["failed", "auth-required"].includes(root.wifi.operation.state) || root.wifi.metadataError.length > 0
            text: root.wifi.operation.lastError || root.wifi.metadataError
            textSize: Design.bodySmallPx
            color: Design.colorVermillion
            wrapMode: Text.WordWrap
        }
        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Redes disponibles")
            detail: qsTr("Los puntos de acceso conservan su identidad por interfaz y BSSID")
        }
        Repeater {
            model: root.sortedNetworks
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                subtitle: root.networkState(modelData) + " · " + Math.round(modelData.signalStrength * 100) + "% · " + WifiSecurityType.toString(modelData.security)
                icon: root.wifi.operationNetwork === modelData && root.wifi.operation.state === "connecting" ? "sync" : "wifi"
                selected: modelData === root.selectedNetwork
                onClicked: root.selectNetwork(modelData)
            }
        }
        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: root.wifi.wifiEnabled && !!root.wifi.wifiDevice && root.sortedNetworks.length === 0
            title: qsTr("El scan no encontró redes")
            detail: qsTr("Acerca el equipo al punto de acceso y vuelve a buscar")
        }
        CortetsuButton { label: qsTr("Buscar redes"); icon: "refresh"; disabled: !root.wifi.wifiEnabled; onClicked: root.refreshAll() }
        CortetsuSurface {
            Layout.fillWidth: true
            visible: !!root.selectedNetwork
            implicitHeight: inspector.implicitHeight + Design.spacingComfortable * 2
            baseColor: Qt.alpha(Design.colorSurfaceGlass, 0.72)
            outlined: true
            radiusValue: Design.radiusMedium
            ColumnLayout {
                id: inspector
                anchors.fill: parent
                anchors.margins: Design.spacingComfortable
                spacing: Design.spacingCompact
                CortetsuSectionHeader { title: root.selectedNetwork?.name ?? ""; detail: root.selectedNetwork ? root.networkState(root.selectedNetwork) : "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Interfaz"); value: root.selectedNetwork?.device?.name ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Seguridad"); value: root.selectedNetwork ? WifiSecurityType.toString(root.selectedNetwork.security) : "" }
                Repeater {
                    model: root.wifi.accessPoints.filter(ap => ap.ssid === root.selectedNetwork?.name && ap.device === root.selectedNetwork?.device?.name)
                    delegate: ConnectionDetail {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.active ? qsTr("AP activo") : qsTr("Punto de acceso")
                        value: modelData.bssid + " · " + (modelData.frequency >= 5925 ? "6 GHz" : modelData.frequency >= 4900 ? "5 GHz" : "2.4 GHz") + " · " + modelData.frequency + " MHz · " + modelData.strength + "%"
                    }
                }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Dirección IP"); value: root.selectedDetails.address ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("IPv6"); value: (root.selectedDetails.ipv6Addresses ?? []).join(", ") }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Puerta de enlace"); value: root.selectedDetails.gateway ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("DNS"); value: (root.selectedDetails.dns ?? []).join(", ") }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("UUID activo"); value: root.selectedDetails.uuid ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Perfil activo"); value: root.selectedDetails.profileName ?? "" }
                TextField {
                    id: password
                    Layout.fillWidth: true
                    visible: !!root.selectedNetwork && !root.selectedNetwork.connected
                    placeholderText: qsTr("Contraseña (si la red la requiere)")
                    echoMode: TextInput.Password
                    color: Design.colorOnSurface
                    onAccepted: root.connectSelected()
                    background: CortetsuSurface { baseColor: Design.colorSurfaceGlassStrong; radiusValue: Design.radiusSmall; outlined: true }
                }
                CortetsuText {
                    Layout.fillWidth: true
                    visible: !!root.selectedNetwork && [WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap, WifiSecurityType.Wpa3SuiteB192, WifiSecurityType.DynamicWep, WifiSecurityType.Leap].includes(root.selectedNetwork.security)
                    text: qsTr("802.1X requiere un perfil con identidad y certificados. Selecciona un perfil configurado; esta página no crea credenciales empresariales.")
                    wrapMode: Text.WordWrap
                    textSize: Design.bodySmallPx
                }
                RowLayout {
                    CortetsuButton { label: qsTr("Conectar / reintentar"); icon: "link"; disabled: !root.selectedNetwork || root.selectedNetwork.connected || root.wifi.connecting; onClicked: root.connectSelected() }
                    CortetsuButton { label: qsTr("Cerrar detalle"); icon: "close"; onClicked: root.selectNetwork(null) }
                }
            }
        }
        CortetsuSectionHeader { title: qsTr("Perfiles guardados"); detail: qsTr("Identificados por UUID, independientemente del nombre de la red") }
        Repeater {
            model: root.wifi.profiles.filter(profile => profile.type === "802-11-wireless")
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                subtitle: (modelData.ssid || qsTr("SSID no disponible")) + " · " + modelData.uuid
                icon: "bookmark"
                selected: modelData.uuid === root.selectedUuid
                onClicked: { root.selectedUuid = modelData.uuid; root.confirmForgetUuid = ""; }
            }
        }
        RowLayout {
            visible: !!root.selectedProfile
            Layout.fillWidth: true
            CortetsuText { Layout.fillWidth: true; text: qsTr("Conectar automáticamente"); textSize: Design.bodySmallPx }
            CortetsuToggle {
                checked: root.selectedProfile?.autoconnect ?? false
                onToggled: value => root.wifi.setAutoconnect(root.selectedUuid, value)
                Accessible.name: qsTr("Autoconexión del perfil")
            }
            CortetsuButton { label: qsTr("Conectar perfil"); icon: "link"; disabled: root.wifi.busy; onClicked: root.wifi.connectProfile(root.selectedUuid) }
            CortetsuButton {
                label: root.confirmForgetUuid === root.selectedUuid ? qsTr("Confirmar olvido") : qsTr("Olvidar perfil")
                icon: "delete"
                danger: true
                onClicked: {
                    if (root.confirmForgetUuid === root.selectedUuid) {
                        root.wifi.forgetProfile(root.selectedUuid);
                        root.selectedUuid = "";
                        root.confirmForgetUuid = "";
                    } else root.confirmForgetUuid = root.selectedUuid;
                }
            }
        }
        NetworkAdvanced {
            Layout.fillWidth: true
            profileUuid: root.selectedUuid
            onProfileSelected: uuid => root.selectedUuid = uuid
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.showVpn
        CortetsuSectionHeader { title: qsTr("VPN"); detail: Connectivity.vpn.active.displayName }
        RowLayout {
            Layout.fillWidth: true
            CortetsuText { Layout.fillWidth: true; text: Connectivity.vpn.status.reason || Connectivity.vpn.status.state; textSize: Design.bodySmallPx }
            CortetsuToggle {
                checked: Connectivity.vpn.connected
                disabled: Connectivity.vpn.connecting || Connectivity.vpn.disconnecting || Connectivity.vpn.providers.length === 0
                onToggled: Connectivity.vpn.toggle()
                Accessible.name: qsTr("Activar VPN")
            }
        }
        Repeater {
            model: Connectivity.vpn.providers
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.displayName || modelData.name
                subtitle: modelData.providerId === Connectivity.vpn.selectedProvider ? qsTr("Proveedor seleccionado") : qsTr("Seleccionar proveedor")
                icon: "vpn_key"
                onClicked: Connectivity.vpn.setActiveProvider(modelData.index)
            }
        }
        }
    }
}
