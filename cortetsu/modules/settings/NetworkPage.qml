pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../components"
import "../../services"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "network"

// Wi-Fi is a workbench: the active link stays visible while the explorer and
// inspector handle discovery, saved profiles and NetworkManager actions.
Item {
    id: root

    required property var screenState
    required property var screen

    property bool showVpn: true
    readonly property var wifi: Connectivity.wifi
    readonly property string scanOwner: "settings-wifi-" + String(root)
    property bool showingProfiles: false
    property int selectedIndex: 0
    property string networkQuery: ""
    property bool strongestFirst: true
    property string copiedProfileUuid: ""
    property bool passwordVisible: false
    property string password: ""

    readonly property var networks: wifi.networks
    readonly property var profiles: wifi.profiles.filter(profile => profile.type === "802-11-wireless")
    readonly property var filteredNetworks: {
        const query = root.networkQuery.trim().toLowerCase();
        const matching = root.networks.filter(network => !query || network.name.toLowerCase().includes(query));
        return matching.slice().sort((left, right) => {
            if (left.connected !== right.connected) return left.connected ? -1 : 1;
            return root.strongestFirst ? right.signalStrength - left.signalStrength : left.name.localeCompare(right.name);
        });
    }
    readonly property var selectedNetwork: root.showingProfiles ? null : root.filteredNetworks[root.selectedIndex] ?? null
    readonly property var activeNetwork: wifi.activeNetwork
    readonly property var activeProfile: root.profiles.find(profile => profile.uuid === root.activeDetails.uuid) ?? null
    readonly property var selectedProfile: {
        if (root.showingProfiles) return root.profiles[root.selectedIndex] ?? null;
        if (!root.selectedNetwork) return null;
        if (root.selectedNetwork.connected) return root.profiles.find(profile => profile.uuid === wifi.details[root.selectedNetwork.device.name]?.uuid) ?? null;
        const matching = root.profiles.filter(profile => profile.ssid === root.selectedNetwork.name
            && (!profile.interface || profile.interface === root.selectedNetwork.device.name));
        return matching.length === 1 ? matching[0] : null;
    }
    readonly property bool selectedIsActive: root.selectedNetwork?.connected ?? false
    readonly property bool selectedNeedsPassword: !!root.selectedNetwork && !root.selectedIsActive
        && [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(root.selectedNetwork.security)
        && (!root.selectedNetwork.known || (wifi.operationNetwork === root.selectedNetwork
            && ["password-required", "authentication-failed"].includes(wifi.operation.lastErrorCode)))
    readonly property bool selectedCanCopyPassword: !!root.selectedProfile && (!root.selectedNetwork
        || [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(root.selectedNetwork.security))
    readonly property string secretState: CortetsuSettingsNetwork.secretState
    readonly property bool compactLayout: width < 700
    readonly property var activeDetails: CortetsuSettingsNetwork.activeDetails

    // Content.qml places the page in the settings Flickable. This is tall
    // enough for the split workbench while still allowing the compact layout
    // to grow naturally when a narrow window wraps it vertically.
    implicitHeight: root.compactLayout ? 1060 : 720

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

    function signalText(signal): string {
        const value = Number(signal ?? -1);
        return value >= 0 ? qsTr("%1%").arg(value) : qsTr("—");
    }

    function networkSignal(network): real { return network ? wifi.strengthPercent(network.signalStrength) : -1; }
    function securityLabel(network): string {
        return !network || network.security === WifiSecurityType.Open ? qsTr("Red abierta") : WifiSecurityType.toString(network.security);
    }
    function networkIsActive(network): bool {
        return !!network && (network.connected ?? (network.uuid === root.activeDetails.uuid));
    }

    function resetSelection(): void {
        selectedIndex = 0;
        password = "";
        passwordVisible = false;
    }

    function refreshDetails(): void {
        const device = root.activeNetwork?.device?.name ?? "";
        if (device.length > 0)
            CortetsuSettingsNetwork.refreshDetails(device);
    }

    function refreshAll(): void {
        CortetsuSettingsNetwork.refreshAll();
        Qt.callLater(root.refreshDetails);
    }

    function connectSelected(): void {
        if (!root.selectedNetwork || wifi.busy) return;
        const secret = root.selectedNeedsPassword ? root.password : "";
        root.password = "";
        root.passwordVisible = false;
        wifi.connectNetwork(root.selectedNetwork, secret, root.selectedProfile);
    }
    function retrySelected(): void {
        if (wifi.operation.kind === "connect" && wifi.operationNetwork === root.selectedNetwork && root.selectedNetwork) root.connectSelected();
        else root.refreshAll();
    }
    function copySelectedPassword(): void {
        if (root.selectedProfile) { root.copiedProfileUuid = root.selectedProfile.uuid; CortetsuSettingsNetwork.copyPassword(root.selectedProfile.uuid); }
    }
    function disconnectActive(): void {
        if (root.activeNetwork) wifi.disconnectNetwork(root.activeNetwork);
    }
    function forgetActive(): void {
        if (root.activeProfile) wifi.forgetProfile(root.activeProfile.uuid);
    }
    function disconnectProfile(): void {
        const network = root.networks.find(item => item.connected && wifi.details[item.device.name]?.uuid === root.selectedProfile?.uuid);
        if (network) wifi.disconnectNetwork(network);
    }
    function detailsValue(value): string {
        return String(value ?? "").length > 0 ? String(value) : qsTr("No disponible");
    }

    onShowingProfilesChanged: resetSelection()
    onNetworkQueryChanged: resetSelection()

    onSelectedNetworkChanged: { root.password = ""; root.passwordVisible = false; CortetsuSettingsNetwork.cancelPasswordCopy(); }
    onSelectedProfileChanged: if (copiedProfileUuid && selectedProfile?.uuid !== copiedProfileUuid) { copiedProfileUuid = ""; CortetsuSettingsNetwork.cancelPasswordCopy(); }
    onVisibleChanged: {
        wifi.setScanOwner(scanOwner, visible);
        if (!visible) { root.password = ""; root.passwordVisible = false; CortetsuSettingsNetwork.cancelPasswordCopy(); }
    }
    Component.onCompleted: { wifi.setScanOwner(scanOwner, visible); Qt.callLater(root.refreshDetails); }
    Component.onDestruction: { wifi.setScanOwner(scanOwner, false); CortetsuSettingsNetwork.cancelPasswordCopy(); }

    Connections {
        target: CortetsuSettingsNetwork

        function onNetworksChanged(): void {
            if (root.selectedIndex >= root.filteredNetworks.length)
                root.resetSelection();
            root.refreshDetails();
        }

        function onProfilesChanged(): void {
            if (root.showingProfiles && root.selectedIndex >= root.profiles.length)
                root.resetSelection();
        }

        function onActiveSsidChanged(): void {
            root.refreshDetails();
        }

        function onActiveDeviceChanged(): void {
            root.refreshDetails();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        CortetsuSurface {
            Layout.fillWidth: true
            visible: CortetsuSettingsNetwork.state === "error"
            implicitHeight: 52
            baseColor: Qt.alpha(CortetsuDesign.colorWarning, 0.12)
            outlineColor: Qt.alpha(CortetsuDesign.colorWarning, 0.54)
            outlined: true
            radiusValue: CortetsuDesign.radiusMedium

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: "warning"
                    color: CortetsuDesign.colorWarning
                    iconSize: CortetsuTypography.iconMediumPx
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: CortetsuSettingsNetwork.error
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorWarning
                    elide: Text.ElideRight
                }

                CortetsuButton {
                    compact: true
                    icon: "refresh"
                    label: qsTr("Reintentar")
                    disabled: CortetsuSettingsNetwork.busy
                    onClicked: root.retrySelected()
                }
            }
        }

        ActiveNetworkCard {
            Layout.fillWidth: true
            page: root
        }

        RowLayout {
            visible: !!root.activeNetwork && root.compactLayout
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuButton {
                compact: true
                danger: true
                icon: "link_off"
                label: qsTr("Desconectar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.disconnectActive()
            }

            CortetsuButton {
                compact: true
                icon: "visibility_off"
                label: qsTr("Olvidar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.forgetActive()
            }
        }

        Flow {
            id: workbench
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingSection
            property bool compact: root.compactLayout
            height: compact
                ? listPanel.implicitHeight + detailPanel.implicitHeight + spacing
                : Math.max(listPanel.implicitHeight, detailPanel.implicitHeight)

            NetworkListPanel {
                id: listPanel
                page: root
                width: workbench.compact
                    ? workbench.width
                    : Math.min(390, Math.max(340, workbench.width * 0.34))
            }

            NetworkDetailPanel {
                id: detailPanel
                page: root
                width: workbench.compact
                    ? workbench.width
                    : Math.max(0, workbench.width - listPanel.width - workbench.spacing)
            }
        }
    }
}
